from pathlib import Path
from types import SimpleNamespace
import unittest

import benchmark_compare as compare
import benchmark_host as host
import benchmark_provenance as provenance
import test_benchmark_compare as fixtures


def rate_run(arm, sequence, users=10):
    arm, metadata, summary = fixtures.run(arm, sequence, users=users)
    contract = provenance.rate_contract(users, 10, 30)
    metadata.update(mode='fixed-rate', workload_contract=contract)
    metadata['workload'] = metadata['provenance']['workload'] = {'sha256': provenance.RATE_SHA256}
    total, measured = 8 * users, 6 * users
    values = summary['metrics']
    for key, count in {'checks': total, 'offered_cycles': total, 'completed_cycles': total,
                       'schedule_lag_ms': total, 'record_read_ms': measured, 'scheduled_cycle_ms': measured,
                       'missed_start_deadlines': 0, 'cycle_deadline_overruns': 0}.items():
        values.setdefault(key, {'values': {}})['values']['passes' if key == 'checks' else 'count'] = count
    values['schedule_lag_ms']['values'].update(min=0, max=20)
    values['scheduled_cycle_ms']['values'].update(min=200, max=800, **{'p(95)': 750})
    summary['root_group']['checks'][1]['passes'] = total - users
    return arm, metadata, summary


class FixedRateTest(unittest.TestCase):
    def test_checked_workload_digest_and_bounded_schedule(self):
        workload = provenance.workload_identity(Path(__file__).parent / 'workloads' / 'school_rate.js')
        args = SimpleNamespace(mode='fixed-rate', users=10, warmup=60, seconds=180)
        contract = provenance.campaign_contract(args, workload)
        self.assertEqual(contract['cycles_per_actor'], 48)
        self.assertEqual(contract['measured_cycles_per_actor'], 36)
        for key, value in [('mode', 'mixed'), ('users', 11), ('users', True), ('warmup', 61),
                           ('warmup', 1), ('seconds', 181), ('seconds', 0), ('seconds', 6)]:
            with self.subTest(key=key, value=value), self.assertRaises(host.GuardError):
                provenance.campaign_contract(SimpleNamespace(**{**vars(args), key: value}), workload)

    def test_equal_rate_comparison_checks_all_cycles_and_reports_schedule(self):
        runs = [rate_run('baseline', 0), rate_run('candidate', 1),
                rate_run('candidate', 2), rate_run('baseline', 3)]
        result = compare.compare(runs, users=[10], repetitions=2)
        row = result['levels'][0]['baseline']['runs'][0]
        self.assertEqual(row['offered_cycles'], 80)
        self.assertEqual(row['verified_cycles_including_warmup'], 80)
        self.assertEqual(row['offered_cycles_per_second'], 2)
        self.assertEqual(row['max_start_lag_ms'], 20)
        self.assertEqual(row['sql_calls_per_verified_cycle'], 200 / 80)
        self.assertEqual(result['conditions']['workload_contract']['interval_ms_per_actor'], 5000)

    def test_dropped_delayed_censored_or_unverified_cycles_fail(self):
        for metric, key, value in [('offered_cycles', 'count', 79), ('completed_cycles', 'count', 79),
                ('business_saves', 'count', 59), ('record_read_ms', 'count', 59),
                ('scheduled_cycle_ms', 'count', 59), ('schedule_lag_ms', 'count', 79),
                ('missed_start_deadlines', 'count', 1), ('cycle_deadline_overruns', 'count', 1),
                ('checks', 'passes', 79), ('schedule_lag_ms', 'max', 251),
                ('scheduled_cycle_ms', 'max', 5001), ('scheduled_cycle_ms', 'max', float('nan'))]:
            _, metadata, summary = rate_run('baseline', 0)
            summary['metrics'][metric]['values'][key] = value
            with self.subTest(metric=metric, key=key), self.assertRaises(host.GuardError):
                compare.inspect_run(metadata, summary)

    def test_fixed_rate_contract_cannot_be_omitted_or_relaxed(self):
        for change in ['missing', 'slower_rate', 'longer_deadline', 'wrong_actor_count']:
            _, metadata, summary = rate_run('baseline', 0)
            if change == 'missing':
                del metadata['workload_contract']
            else:
                key = {'slower_rate': 'interval_ms_per_actor', 'longer_deadline': 'max_start_lag_ms',
                       'wrong_actor_count': 'actors'}[change]
                metadata['workload_contract'][key] *= 2
            with self.subTest(change=change), self.assertRaises(host.GuardError):
                compare.inspect_run(metadata, summary)

    def test_closed_and_fixed_rate_runs_cannot_be_combined(self):
        runs = [fixtures.run('baseline', 0, users=10), rate_run('candidate', 1),
                rate_run('candidate', 2), rate_run('baseline', 3)]
        with self.assertRaisesRegex(host.GuardError, 'conditions'):
            compare.compare(runs, users=[10], repetitions=2)
