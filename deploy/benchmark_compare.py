"""Compare complete, matching school campaigns without pooling run percentiles."""
import argparse
from datetime import datetime
import json
from pathlib import Path
import statistics

import benchmark_host as host
import benchmark_metrics as metrics
import benchmark_provenance as provenance


COMPARABLE = ("fixture", "workload", "k6_image", "postgres_image", "resources",
              "postgres_metrics_settings", "host_controller_sha256", "target", "transport",
              "statement_statistics_available")
FINAL_CHECK = "final fresh read confirms persisted save"
READ_CHECK = "fresh authorized read retains last saved value"


def inspect_run(metadata, summary):
    """Validate actual identities, correctness and counter epochs before reduction."""
    m, p, r, values = metadata, metadata["provenance"], metadata["restoration"], summary["metrics"]
    application = host.validate_application(m["application"])
    host.require(m["status"] == "passed" and m["k6_exit_code"] == 0 and m["mode"] == "mixed",
                 "Comparison requires successful mixed browser campaigns")
    host.require(application == p["application"] == r["application"]
                 and r["final_identity"]["application_commit"] == application["application_commit"]
                 and r["final_identity"]["image"] == application["image"]
                 and r["operation_id"] == p["operation_id"]
                 and r["status"] == "finish" and r["restoration"]["status"] == "recovered"
                 and r["restoration"]["operation_id"] == r["operation_id"],
                 "Application identity or restoration mismatch")
    host.require(p["fixture"] == m["fixture"] and p["workload"] == m["workload"]
                 and p["workload"]["sha256"] == provenance.WORKLOAD_SHA256,
                 "Fixture or reviewed workload mismatch")
    host.require(p["statement_statistics_available"], "Comparison requires statement statistics")
    delta = metrics.difference(r["metrics_before"], r["metrics_after"])
    host.require(delta == r["metrics_delta"]
                 and delta["settings"] == p["postgres_metrics_settings"], "Counter report mismatch")
    checks = values["checks"]["values"]
    host.require(checks["fails"] == 0 and checks["passes"] > 0
                 and values["business_failure"]["values"]["rate"] == 0,
                 "Failed browser correctness checks")
    grouped = summary["root_group"]
    host.require(not grouped["groups"], "Unexpected nested workload checks")
    by_name = {check["name"]: check for check in grouped["checks"]}
    host.require(len(by_name) == len(grouped["checks"]) and set(by_name) == {FINAL_CHECK, READ_CHECK}
                 and all(check["fails"] == 0 for check in by_name.values())
                 and by_name[FINAL_CHECK]["passes"] == m["users"]
                 and sum(check["passes"] for check in by_name.values()) == checks["passes"],
                 "Cannot derive full-cycle count from workload checks")
    # For each actor, N cycles produce N-1 checked revisits and one checked
    # final read. Includes warmup and the final cycle crossing the window end.
    cycles = checks["passes"]
    saves = values["business_saves"]["values"]["count"]
    host.require(0 < saves <= cycles and values["save_ack_ms"]["values"]["count"] == saves,
                 "Measured save count mismatch")
    host.require(values["measurement_end_unix_ms"]["values"]["value"]
                 - values["measurement_start_unix_ms"]["values"]["value"]
                 == m["measurement_seconds"] * 1000, "Business measurement window mismatch")
    host.require(timestamp(m["started_at"]) <= r["metrics_before"]["unix_time"]
                 <= values["measurement_start_unix_ms"]["values"]["value"] / 1000
                 < values["measurement_end_unix_ms"]["values"]["value"] / 1000
                 <= r["metrics_after"]["unix_time"] <= timestamp(m["ended_at"]),
                 "Business measurement is outside the observed campaign interval")
    sql_calls = sum(query["calls"] for query in delta["statements"])
    db_seconds = delta["cpu"]["db"]["usage_usec"] / 1_000_000
    web_seconds = delta["cpu"]["web"]["usage_usec"] / 1_000_000
    before_pending = r["metrics_before"]["activity"]["pending_outbox"]
    after_pending = r["metrics_after"]["activity"]["pending_outbox"]
    row = {
        "operation_id": r["operation_id"], "users": m["users"],
        "started_at": m["started_at"], "ended_at": m["ended_at"],
        "measured_saves": saves, "verified_cycles_including_warmup": cycles,
        "save_ack_p95_ms": values["save_ack_ms"]["values"]["p(95)"],
        "record_read_p95_ms": values["record_read_ms"]["values"]["p(95)"],
        "measured_saves_per_second": saves / m["measurement_seconds"],
        "observation_seconds": delta["window_seconds"], "sql_calls": sql_calls,
        "sql_calls_per_verified_cycle": sql_calls / cycles,
        "statement_execution_ms": sum(query["total_exec_time"] for query in delta["statements"]),
        "database_cpu_seconds": db_seconds, "web_cpu_seconds": web_seconds,
        "database_cpu_seconds_per_verified_cycle": db_seconds / cycles,
        "web_cpu_seconds_per_verified_cycle": web_seconds / cycles,
        "database_average_cpu_cores": db_seconds / delta["window_seconds"],
        "web_average_cpu_cores": web_seconds / delta["window_seconds"],
        "cpu_throttled_usec": {service: delta["cpu"][service]["throttled_usec"] for service in ["web", "db"]},
        "deadlocks": delta["database"]["deadlocks"],
        "pending_outbox_before": before_pending, "pending_outbox_after": after_pending,
        "restoration_confirmed": True,
    }
    signature = {key: p[key] for key in COMPARABLE}
    signature.update({key: m[key] for key in ["runner", "route_verification", "mode", "warmup_seconds", "measurement_seconds"]})
    return application, signature, row


def spread(values):
    return {"min": min(values), "median": statistics.median(values), "max": max(values)}


def timestamp(value):
    parsed = datetime.fromisoformat(value)
    host.require(parsed.tzinfo is not None, "Campaign timestamp lacks timezone")
    return parsed.timestamp()


def compare(runs, *, users=(1, 5, 10), repetitions=3):
    """Require the declared matrix; missing/failed/mismatched runs fail closed."""
    host.require(repetitions >= 2 and users and len(set(users)) == len(users) and all(1 <= n <= 10 for n in users),
                 "Invalid repeated comparison matrix")
    identities, signature, groups, operations = {}, None, {}, set()
    for arm, metadata, summary in runs:
        host.require(arm in {"baseline", "candidate"}, "Unknown comparison arm")
        application, observed, row = inspect_run(metadata, summary)
        host.require(row["operation_id"] not in operations, "Duplicate campaign operation")
        operations.add(row["operation_id"])
        host.require(row["users"] in users, "Undeclared concurrency level")
        if signature is None:
            signature = observed
        host.require(signature == observed, "Campaign conditions or runner/controller provenance differ")
        identities.setdefault(arm, application)
        host.require(identities[arm] == application, "Application changed within comparison arm")
        host.require((arm == "baseline" and application == host.baseline_application())
                     or (arm == "candidate" and application["schema"] == 2), "Wrong baseline/candidate application")
        groups.setdefault((arm, row["users"]), []).append(row)
    host.require(set(groups) == {(arm, n) for arm in ["baseline", "candidate"] for n in users}
                 and all(len(rows) == repetitions for rows in groups.values()), "Incomplete or oversized comparison matrix")
    ordered = sorted((row for rows in groups.values() for row in rows), key=lambda row: timestamp(row["started_at"]))
    host.require(all(timestamp(left["ended_at"]) <= timestamp(right["started_at"]) for left, right in zip(ordered, ordered[1:])),
                 "Campaign observation periods overlap")
    fields = ["save_ack_p95_ms", "record_read_p95_ms", "measured_saves_per_second",
              "sql_calls_per_verified_cycle", "database_cpu_seconds_per_verified_cycle",
              "web_cpu_seconds_per_verified_cycle", "database_average_cpu_cores", "web_average_cpu_cores"]
    levels = []
    for n in users:
        arms = {arm: {"runs": sorted(groups[(arm, n)], key=lambda row: timestamp(row["started_at"])),
                      "variation": {field: spread([row[field] for row in groups[(arm, n)]]) for field in fields}}
                for arm in ["baseline", "candidate"]}
        changes = {}
        for field in fields:
            baseline, candidate = (arms[arm]["variation"][field]["median"] for arm in ["baseline", "candidate"])
            changes[field] = None if baseline == 0 else (candidate / baseline - 1) * 100
        levels.append({"users": n, **arms, "median_change_percent": changes})
    return {"schema": 1, "applications": identities, "conditions": signature,
            "repetitions_per_arm_and_level": repetitions, "levels": levels,
            "original_timing_and_repetitions": signature["warmup_seconds"] == 60
                and signature["measurement_seconds"] == 180 and repetitions == 3,
            "interpretation": [
                "Latency summaries are medians/ranges of per-run p95 values, never pooled percentiles or confidence intervals.",
                "Full-window SQL/CPU per verified cycle includes browser initialization, warmup, final reads, background work and observers.",
                "Closed workload throughput is not an equal-offered-rate headroom comparison.",
                "No supported-capacity claim: the remaining contention, volume and longer-duration matrix must pass."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", action="append", type=Path, required=True)
    parser.add_argument("--candidate", action="append", type=Path, required=True)
    parser.add_argument("--users", type=int, nargs="+", default=[1, 5, 10])
    parser.add_argument("--repetitions", type=int, default=3)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    runs = [(arm, json.loads((path / "metadata.json").read_text()), json.loads((path / "summary.json").read_text()))
            for arm in ["baseline", "candidate"] for path in getattr(args, arm)]
    report = compare(runs, users=args.users, repetitions=args.repetitions)
    with args.output.open("x") as stream:
        stream.write(json.dumps(report, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    try:
        main()
    except host.GuardError as error:
        raise SystemExit(str(error)) from None
