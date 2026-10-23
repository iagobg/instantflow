"""Run the declared Sprint 11 final workload without concurrent build/test activity."""
import argparse
import json
import re
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('phase', help='Unique retained result label')
parser.add_argument('--group', choices=['all', 'core', 'support'], default='all')
args = parser.parse_args()
PHASE = args.phase
if not re.fullmatch(r'[a-z][a-z0-9-]*', PHASE):
    parser.error('phase must be a lowercase filename label')
def validate(report):
    for phase in ('cold', 'warm'):
        data = report[phase]
        overall = data['overall']
        assert overall['backend_p95_ms'] <= 500, (phase, 'overall latency')
        assert data['maximum_tenant_backend_p95_ms'] <= 500, (phase, 'tenant latency')
        assert overall['max_observed_memory_growth_bytes'] <= 33554432, (phase, 'caller memory')
        assert data['vm']['vm_growth_per_concurrent_worker_bytes'] <= 33554432, (phase, 'VM aggregate per worker')
        assert overall['max_fetched_json_bytes'] <= 4194304, (phase, 'decoded payload')
        assert overall['max_returned_rows'] <= 25, (phase, 'page')
        assert data['vm']['postgres_wire']['valid'], (phase, 'TCP counters')

if args.group in ('all', 'core'):
    result = subprocess.run(['python3', 'scripts/benchmark_read_matrix.py', PHASE], cwd=ROOT)
    if result.returncode:
        raise SystemExit(result.returncode)
if args.group in ('all', 'core'):
    for path in sorted((ROOT / '.local').glob('sprint11-read-*-' + PHASE + '.json')):
        validate(json.loads(path.read_text()))
if args.group == 'core':
    raise SystemExit(0)

cases = [
    ('operations-equal', 'benchmark_support_reads.exs', {}),
    ('operations-uneven', 'benchmark_support_reads.exs', {'READ_SHAPE': 'uneven'}),
    ('participants-processes-100', 'benchmark_participant_reads.exs', {'READ_PROCESSES': '100', 'READ_SURFACE': 'participants'}),
    ('messages-processes-100', 'benchmark_participant_reads.exs', {'READ_PROCESSES': '100', 'READ_SURFACE': 'messages'}),
    ('participants-uneven', 'benchmark_participant_reads.exs', {'READ_PROCESSES': '100', 'READ_SURFACE': 'participants', 'READ_SHAPE': 'uneven'}),
    ('messages-uneven', 'benchmark_participant_reads.exs', {'READ_PROCESSES': '100', 'READ_SURFACE': 'messages', 'READ_SHAPE': 'uneven'}),
    ('participants-active-pins-100', 'benchmark_participant_reads.exs', {'READ_VERSIONS': '100', 'READ_USED_VERSIONS': '100', 'READ_SURFACE': 'participants'}),
    ('messages-active-pins-100', 'benchmark_participant_reads.exs', {'READ_VERSIONS': '100', 'READ_USED_VERSIONS': '100', 'READ_SURFACE': 'messages'}),
]
cases += [(surface + '-wide', 'benchmark_reads.exs', {'READ_SURFACE': surface, 'READ_PROCESSES': '100', 'READ_VERSIONS': '100', 'READ_WIDTH': '50'}) for surface in ('catalog', 'creation', 'navigation')]
for name, script, settings in cases:
    prefix = ROOT / '.local' / ('sprint11-acceptance-' + name + '-' + PHASE)
    report_path = prefix.with_suffix('.json')
    if report_path.exists():
        raise SystemExit('Refusing to overwrite retained report: ' + str(report_path))
    env = {k: v for k, v in os.environ.items() if not k.startswith('READ_')}
    env.update(settings, READ_REPORT=str(report_path))
    with prefix.with_suffix('.log').open('w') as log:
        result = subprocess.run(['mix', 'run', '--no-start', 'scripts/' + script], cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        print(prefix.with_suffix('.log').read_text()[-5000:], flush=True)
        raise SystemExit(result.returncode)
    report = json.loads(report_path.read_text())
    validate(report)
    print(json.dumps({'case': name, 'warm': report['warm']['overall'], 'max_tenant_p95_ms': report['warm']['maximum_tenant_backend_p95_ms']}), flush=True)
