import copy
from datetime import datetime, timezone
import unittest

import benchmark_compare as compare
import benchmark_host as host
import benchmark_metrics as metrics
import benchmark_provenance as provenance
from test_benchmark_metrics import counters
from test_benchmark_rollout import candidate


def run(arm, sequence, *, users=1, latency=100):
    application = host.baseline_application() if arm == "baseline" else candidate()
    operation = "operation-" + str(sequence)
    start = 1_790_000_000 + sequence * 120
    before = counters()
    before.update({"unix_time": start + 10, "activity": {"pending_outbox": {"count": 0, "oldest_seconds": None}},
                   "statements_available": True, "statements": {"info": {"dealloc": 0}, "queries": []}})
    after = copy.deepcopy(before)
    after["unix_time"] = start + 90
    after["cpu"]["db"]["usage_usec"] += 2_000_000
    after["cpu"]["web"]["usage_usec"] += 1_000_000
    after["statements"]["queries"] = [{"query_id": "123", "toplevel": True,
        **dict.fromkeys(metrics.STATEMENT_COUNTERS, 0), "calls": 200, "total_exec_time": 10}]
    fixture = {"name": "school-v1"}
    workload = {"sha256": provenance.WORKLOAD_SHA256}
    p = {key: "fixed" for key in compare.COMPARABLE}
    p.update({"application": application, "operation_id": operation, "fixture": fixture, "workload": workload,
              "postgres_metrics_settings": before["settings"], "statement_statistics_available": True})
    metadata = {"application": application, "provenance": p, "fixture": fixture, "workload": workload,
        "status": "passed", "mode": "mixed", "k6_exit_code": 0, "users": users,
        "warmup_seconds": 10, "measurement_seconds": 30, "runner": {"source_sha256": "runner"},
        "route_verification": {"tls_verified": True},
        "started_at": datetime.fromtimestamp(start, timezone.utc).isoformat(),
        "ended_at": datetime.fromtimestamp(start + 110, timezone.utc).isoformat(),
        "restoration": {"application": application, "operation_id": operation, "status": "finish",
            "final_identity": {"application_commit": application["application_commit"], "image": application["image"]},
            "restoration": {"status": "recovered", "operation_id": operation},
            "metrics_before": before, "metrics_after": after, "metrics_delta": metrics.difference(before, after)}}
    values = {"checks": {"passes": 10 * users, "fails": 0}, "business_failure": {"rate": 0},
        "business_saves": {"count": 6 * users}, "save_ack_ms": {"count": 6 * users, "p(95)": latency},
        "record_read_ms": {"p(95)": 2 * latency},
        "measurement_start_unix_ms": {"value": (start + 40) * 1000},
        "measurement_end_unix_ms": {"value": (start + 70) * 1000}}
    summary = {"metrics": {key: {"values": value} for key, value in values.items()},
               "root_group": {"groups": [], "checks": [
                   {"name": compare.FINAL_CHECK, "passes": users, "fails": 0},
                   {"name": compare.READ_CHECK, "passes": 9 * users, "fails": 0}]}}
    return arm, metadata, summary


class ComparisonTest(unittest.TestCase):
    def matrix(self):
        return [run("baseline", 0, latency=100), run("candidate", 1, latency=50),
                run("candidate", 2, latency=150), run("baseline", 3, latency=300)]

    def test_reports_per_run_variation_and_amortizes_full_cycles_including_warmup(self):
        result = compare.compare(self.matrix(), users=[1], repetitions=2)
        level = result["levels"][0]
        self.assertEqual(level["baseline"]["variation"]["save_ack_p95_ms"], {"min": 100, "median": 200, "max": 300})
        self.assertEqual(level["median_change_percent"]["save_ack_p95_ms"], -50)
        row = level["baseline"]["runs"][0]
        self.assertEqual(row["measured_saves"], 6)
        self.assertEqual(row["verified_cycles_including_warmup"], 10)
        self.assertEqual(row["sql_calls_per_verified_cycle"], 20)
        self.assertEqual(row["database_cpu_seconds_per_verified_cycle"], .2)
        self.assertFalse(result["original_timing_and_repetitions"])

    def test_missing_duplicate_extra_or_undeclared_runs_cannot_pass(self):
        for runs, users in [(self.matrix()[:-1], [1]), (self.matrix() + [self.matrix()[0]], [1]),
                            (self.matrix(), [1, 5]), (self.matrix(), [5])]:
            with self.subTest(users=users, count=len(runs)), self.assertRaises(host.GuardError):
                compare.compare(runs, users=users, repetitions=2)

    def test_failed_workload_restore_identity_or_save_count_is_rejected(self):
        for path, value in [(('status',), 'failed'), (('k6_exit_code',), 1),
                (('restoration', 'status'), 'abort'), (('restoration', 'restoration', 'status'), 'failed'),
                (('restoration', 'restoration', 'operation_id'), 'different'),
                (('restoration', 'final_identity', 'application_commit'), 'a' * 40)]:
            runs = self.matrix()
            target = runs[0][1]
            for key in path[:-1]:
                target = target[key]
            target[path[-1]] = value
            with self.subTest(path=path), self.assertRaises(host.GuardError):
                compare.compare(runs, users=[1], repetitions=2)
        runs = self.matrix()
        runs[0][2]['metrics']['business_saves']['values']['count'] = 7
        with self.assertRaisesRegex(host.GuardError, 'save count'):
            compare.compare(runs, users=[1], repetitions=2)

    def test_different_instrumentation_resources_runner_or_workload_is_rejected(self):
        for key in ['resources', 'host_controller_sha256', 'k6_image', 'transport']:
            runs = self.matrix()
            runs[1][1]['provenance'][key] = 'different'
            with self.subTest(key=key), self.assertRaisesRegex(host.GuardError, 'conditions'):
                compare.compare(runs, users=[1], repetitions=2)
        for key in ['runner', 'route_verification', 'warmup_seconds']:
            runs = self.matrix()
            runs[1][1][key] = 'different'
            with self.subTest(key=key), self.assertRaises(host.GuardError):
                compare.compare(runs, users=[1], repetitions=2)
        runs = self.matrix()
        runs[1][1]['workload']['sha256'] = 'unreviewed'
        with self.assertRaisesRegex(host.GuardError, 'workload'):
            compare.compare(runs, users=[1], repetitions=2)

    def test_recomputes_deltas_and_refuses_resets_or_manipulated_reports(self):
        for section, key, value in [('metrics_delta', 'window_seconds', 1),
                                   ('metrics_after', 'cpu_identity', {'web': 'restarted'})]:
            runs = self.matrix()
            runs[0][1]['restoration'][section][key] = value
            with self.subTest(section=section), self.assertRaises(host.GuardError):
                compare.compare(runs, users=[1], repetitions=2)

    def test_missing_final_read_or_changed_check_shape_cannot_count_cycles(self):
        for mutation in ['missing_final', 'extra_check', 'failed_check']:
            runs = self.matrix()
            checks = runs[0][2]['root_group']['checks']
            if mutation == 'missing_final':
                checks[0]['passes'] = 0
            elif mutation == 'extra_check':
                checks.append({'name': 'extra', 'passes': 1, 'fails': 0})
            else:
                checks[1]['fails'] = 1
            with self.subTest(mutation=mutation), self.assertRaises(host.GuardError):
                compare.compare(runs, users=[1], repetitions=2)

    def test_wrong_window_or_measurement_outside_observed_interval_is_rejected(self):
        for offset in [1, 100_000]:
            runs = self.matrix()
            values = runs[0][2]['metrics']
            values['measurement_end_unix_ms']['values']['value'] += offset
            if offset > 1:
                values['measurement_start_unix_ms']['values']['value'] += offset
            with self.subTest(offset=offset), self.assertRaises(host.GuardError):
                compare.compare(runs, users=[1], repetitions=2)

    def test_overlapping_runs_are_rejected_even_if_each_run_is_valid(self):
        runs = [run('baseline', 0), run('candidate', 0), run('baseline', 2), run('candidate', 3)]
        m = runs[1][1]
        m['provenance']['operation_id'] = m['restoration']['operation_id'] = 'distinct'
        m['restoration']['restoration']['operation_id'] = 'distinct'
        with self.assertRaisesRegex(host.GuardError, 'overlap'):
            compare.compare(runs, users=[1], repetitions=2)


class ResourceSamplesTest(unittest.TestCase):
    def inputs(self):
        _, metadata, summary = run('baseline', 0)
        start = summary['metrics']['measurement_start_unix_ms']['values']['value'] / 1000
        events = [{'event': 'ready'}]
        for offset, db, web in [(-10, 99, 199), (1, 98, 198), (5, 20, 40), (15, 40, 80), (29, 97, 197), (40, 96, 196)]:
            events.append({'event': 'sample', 'sample': {'unix_time': start + offset, 'containers': [
                {'Name': host.PROJECT + '-db', 'CPUPerc': str(db) + '%'},
                {'Name': host.PROJECT + '-web', 'CPUPerc': str(web) + '%'}]}})
        return events, summary, {'db_cpus': 1, 'web_cpus': 2}

    def test_excludes_startup_boundary_and_final_reads_and_normalizes_quota(self):
        result = compare.sampled_resources(*self.inputs())
        self.assertEqual(result['samples'], 2)
        self.assertEqual(result['services']['db']['cpu_percent_of_one_core'], {'min': 20, 'median': 30, 'max': 40})
        self.assertEqual(result['services']['web']['cpu_percent_of_one_core']['median'], 60)
        self.assertEqual(result['services']['web']['cpu_percent_of_quota']['median'], 30)

    def test_missing_phase_samples_cannot_be_reported_as_idle_cpu(self):
        events, summary, resources = self.inputs()
        with self.assertRaisesRegex(host.GuardError, 'Insufficient'):
            compare.sampled_resources(events[:3], summary, resources)

    def test_wrong_container_nonfinite_cpu_or_invalid_quota_is_rejected(self):
        for mutation in ['container', 'nan', 'negative', 'quota']:
            events, summary, resources = self.inputs()
            if mutation == 'container':
                events[3]['sample']['containers'][0]['Name'] = 'serving-db'
            elif mutation == 'quota':
                resources['db_cpus'] = 0
            else:
                events[3]['sample']['containers'][0]['CPUPerc'] = 'nan%' if mutation == 'nan' else '-1%'
            with self.subTest(mutation=mutation), self.assertRaises(host.GuardError):
                compare.sampled_resources(events, summary, resources)
