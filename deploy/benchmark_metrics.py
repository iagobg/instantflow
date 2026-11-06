"""Aggregate PostgreSQL/cgroup observations. Never export SQL text or parameters."""
import json
import time

import benchmark_host as host

DATABASE_COUNTERS = ("xact_commit", "xact_rollback", "blks_read", "blks_hit", "tup_returned", "tup_fetched",
                     "tup_inserted", "tup_updated", "tup_deleted", "conflicts", "temp_files", "temp_bytes",
                     "deadlocks", "blk_read_time", "blk_write_time", "session_time", "active_time",
                     "idle_in_transaction_time", "sessions", "sessions_abandoned", "sessions_fatal", "sessions_killed")
WAL_COUNTERS = ("wal_records", "wal_fpi", "wal_bytes", "wal_buffers_full", "wal_write", "wal_sync",
                "wal_write_time", "wal_sync_time")
CPU_COUNTERS = ("usage_usec", "user_usec", "system_usec", "nr_periods", "nr_throttled", "throttled_usec")
STATEMENT_COUNTERS = ("calls", "total_exec_time", "rows", "shared_blks_hit", "shared_blks_read",
                      "shared_blks_dirtied", "shared_blks_written", "temp_blks_read", "temp_blks_written",
                      "blk_read_time", "blk_write_time", "wal_records", "wal_fpi", "wal_bytes")

COUNTERS_SQL = """
SET statement_timeout='5s';
SELECT json_build_object(
 'database', (SELECT row_to_json(d) FROM (SELECT datid, stats_reset, DB_COLUMNS
             FROM pg_stat_database WHERE datname=current_database()) d),
 'wal', (SELECT row_to_json(w) FROM pg_stat_wal w),
 'settings', json_build_object('server_version_num', current_setting('server_version_num'),
   'track_activities', current_setting('track_activities'), 'track_counts', current_setting('track_counts'),
   'track_io_timing', current_setting('track_io_timing'), 'track_wal_io_timing', current_setting('track_wal_io_timing'),
   'shared_preload_libraries', current_setting('shared_preload_libraries')),
 'statements_available', EXISTS(SELECT FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace
   WHERE e.extname='pg_stat_statements' AND n.nspname='instantflow_benchmark_metrics')
   AND 'pg_stat_statements'=ANY(string_to_array(current_setting('shared_preload_libraries'), ','))
);
""".replace("DB_COLUMNS", ", ".join(DATABASE_COUNTERS))

ACTIVITY_SQL = """
SET statement_timeout='5s';
SELECT json_build_object(
 'backends', (SELECT coalesce(json_agg(s), '[]') FROM (
   SELECT state, wait_event_type, wait_event, count(*) AS count,
          max(extract(epoch FROM (clock_timestamp()-xact_start))) AS oldest_transaction_seconds
   FROM pg_stat_activity WHERE datname=current_database() AND usename='instantflow_runtime'
   GROUP BY state, wait_event_type, wait_event ORDER BY state, wait_event_type, wait_event) s),
 'locks', (SELECT coalesce(json_agg(l), '[]') FROM (
   SELECT l.locktype, l.mode, l.granted, count(*) AS count
   FROM pg_locks l JOIN pg_stat_activity a ON a.pid=l.pid
   WHERE a.datname=current_database() AND a.usename='instantflow_runtime'
   GROUP BY l.locktype,l.mode,l.granted ORDER BY l.locktype,l.mode,l.granted) l),
 'pending_outbox', (SELECT json_build_object('count', count(*),
   'oldest_seconds', max(extract(epoch FROM (clock_timestamp()-inserted_at))))
   FROM public.outbox_messages WHERE status='pending')
);
"""

STATEMENTS_SQL = """
SET statement_timeout='5s';
SELECT json_build_object(
 'info', (SELECT row_to_json(i) FROM instantflow_benchmark_metrics.pg_stat_statements_info i),
 'queries', (SELECT coalesce(json_agg(s), '[]') FROM (
    SELECT queryid::text AS query_id, toplevel, STMT_COLUMNS
    FROM instantflow_benchmark_metrics.pg_stat_statements
    WHERE dbid=(SELECT oid FROM pg_database WHERE datname=current_database())
      AND userid=(SELECT oid FROM pg_roles WHERE rolname='instantflow_runtime')
    ORDER BY queryid, toplevel) s));
""".replace("STMT_COLUMNS", ", ".join(STATEMENT_COUNTERS))


def ensure_extension(controller):
    config = host.read_json(host.ROOT / "compose.json")
    if config["services"]["db"].get("command") != host.METRICS_COMMAND:
        return
    host.require(controller.sql(host.DATABASE, "SHOW shared_preload_libraries;") == "pg_stat_statements",
                 "Statement statistics were not preloaded")
    schema = controller.sql(host.DATABASE,
        "SELECT coalesce((SELECT extnamespace::regnamespace::text FROM pg_extension WHERE extname='pg_stat_statements'), '');")
    host.require(schema in {"", "instantflow_benchmark_metrics"}, "Unexpected statement extension schema")
    controller.sql(host.DATABASE, """
        CREATE SCHEMA IF NOT EXISTS instantflow_benchmark_metrics AUTHORIZATION postgres;
        REVOKE ALL ON SCHEMA instantflow_benchmark_metrics FROM PUBLIC, instantflow_runtime;
        CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA instantflow_benchmark_metrics;
    """)


def cpu_counters(text):
    values = dict(line.split() for line in text.splitlines())
    host.require(set(CPU_COUNTERS) <= values.keys(), "Required cgroup v2 CPU counters unavailable")
    return {name: int(values[name]) for name in CPU_COUNTERS}


def capture(controller, *, activity_only=False):
    started = time.monotonic()
    sample = {"unix_time": time.time(), "activity": json.loads(controller.sql(host.DATABASE, ACTIVITY_SQL))}
    if not activity_only:
        sample.update(json.loads(controller.sql(host.DATABASE, COUNTERS_SQL)))
        identities = controller.docker("inspect", "--format",
            '{"id":{{json .Id}},"started_at":{{json .State.StartedAt}}}',
            host.PROJECT + "-web", host.PROJECT + "-db", label="counter container identity", timeout=10)
        identities = [json.loads(line) for line in identities.decode().splitlines()]
        host.require(len(identities) == 2, "Missing counter container identity")
        sample["cpu_identity"] = dict(zip(["web", "db"], identities))
        sample["cpu"] = {}
        for service in ["web", "db"]:
            data = controller.docker("exec", host.PROJECT + "-" + service, "cat", "/sys/fs/cgroup/cpu.stat",
                                     label="cgroup CPU counters", timeout=10)
            sample["cpu"][service] = cpu_counters(data.decode())
        if sample["statements_available"]:
            sample["statements"] = json.loads(controller.sql(host.DATABASE, STATEMENTS_SQL))
    sample["observer_seconds"] = time.monotonic() - started
    return sample


def counter_delta(before, after, names):
    result = {}
    for name in names:
        host.require(isinstance(before[name], (int, float)) and isinstance(after[name], (int, float))
                     and after[name] >= before[name], "Counter decreased or became unavailable: " + name)
        result[name] = after[name] - before[name]
    return result


def difference(before, after):
    host.require(before["database"]["datid"] == after["database"]["datid"]
                 and before["database"]["stats_reset"] == after["database"]["stats_reset"]
                 and before["wal"]["stats_reset"] == after["wal"]["stats_reset"]
                 and before["settings"] == after["settings"]
                 and before["cpu_identity"] == after["cpu_identity"]
                 and before["statements_available"] == after["statements_available"],
                 "Statistics identity, settings or reset epoch changed")
    result = {"window_seconds": after["unix_time"] - before["unix_time"],
              "database": counter_delta(before["database"], after["database"], DATABASE_COUNTERS),
              "wal": counter_delta(before["wal"], after["wal"], WAL_COUNTERS),
              "cpu": {service: counter_delta(before["cpu"][service], after["cpu"][service], CPU_COUNTERS)
                      for service in ["web", "db"]}, "settings": before["settings"],
              "statement_statistics_available": before["statements_available"],
              "scope": "Prepared application to browser completion: includes startup/login, warmup, idle/background work and observers",
              "limits": ["Database transaction/session counters include operator sampling connections",
                         "PostgreSQL counters can lag backend activity; no global reset or forced flush is used",
                         "Backend state samples do not measure application connection checkout/holding time",
                         "cgroup counter reads run brief cat processes inside each measured container",
                         "I/O timing is meaningful only when its corresponding setting is on"]}
    host.require(result["window_seconds"] > 0, "Invalid observation window")
    if before["statements_available"]:
        old, new = before["statements"], after["statements"]
        host.require(old["info"] == new["info"], "Statement statistics reset or entries evicted")
        def indexed(rows):
            return {(q["query_id"], q["toplevel"]): q for q in rows}
        old_queries, new_queries = indexed(old["queries"]), indexed(new["queries"])
        host.require(old_queries.keys() <= new_queries.keys(), "Statement statistics disappeared")
        queries = []
        for key, query in new_queries.items():
            previous = old_queries.get(key, dict.fromkeys(STATEMENT_COUNTERS, 0))
            delta = counter_delta(previous, query, STATEMENT_COUNTERS)
            if delta["calls"]:
                queries.append({"query_id": key[0], "toplevel": key[1], **delta})
        result["statements"] = sorted(queries, key=lambda q: q["total_exec_time"], reverse=True)
    return result
