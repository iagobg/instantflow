import argparse, os, subprocess, json, re
from pathlib import Path
root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description='Run the fixed Sprint 11 backend supporting-volume cases.')
parser.add_argument('phase', help='Unique result label, such as before or indexed')
parser.add_argument('--reuse-existing', action='store_true', help='Explicitly include retained existing reports instead of running them again')
args=parser.parse_args()
phase=args.phase
if not re.fullmatch(r'[a-z][a-z0-9-]*',phase):
 parser.error('phase must be a lowercase filename label')
profiles=[
 ('baseline',{}),
 ('idle-versions-10',{'READ_VERSIONS':'10'}),
 ('idle-versions',{'READ_VERSIONS':'100'}),
 ('mixed-versions-10',{'READ_VERSIONS':'10','READ_USED_VERSIONS':'10'}),
 ('mixed-versions-100',{'READ_VERSIONS':'100','READ_USED_VERSIONS':'100'}),
 ('idle-processes-10',{'READ_PROCESSES':'10','READ_SURFACE':'options'}),
 ('idle-processes-100',{'READ_PROCESSES':'100','READ_SURFACE':'options'}),
 ('hidden-9',{'READ_HIDDEN':'9'}),('hidden-99',{'READ_HIDDEN':'99'}),
 ('width-10',{'READ_WIDTH':'10'}),('width-50',{'READ_WIDTH':'50'}),
 ('uneven',{'READ_SHAPE':'uneven'}),
 ('uneven-mixed-100',{'READ_SHAPE':'uneven','READ_VERSIONS':'100','READ_USED_VERSIONS':'100'})
]
for name,settings in profiles:
 path='.local/sprint11-read-'+name+'-'+phase
 if (root/(path+'.json')).exists() and not args.reuse_existing:
  parser.error('report already exists: '+path+'.json; choose another phase or explicitly reuse it')
 if not (root/(path+'.json')).exists():
  env={k:v for k,v in os.environ.items() if not k.startswith('READ_')}
  env.update(settings,READ_REPORT=path+'.json')
  with (root/(path+'.log')).open('w') as log:
   result=subprocess.run(['mix','run','--no-start','scripts/benchmark_reads.exs'],cwd=root,env=env,stdout=log,stderr=subprocess.STDOUT)
  if result.returncode:
   print((root/(path+'.log')).read_text()[-4000:],flush=True)
   raise SystemExit(result.returncode)
 report=json.loads((root/(path+'.json')).read_text())
 stats=report['warm']['overall']
 print(json.dumps({'case':name,'phase':phase,'backend_p95_ms':stats['backend_p95_ms'],'max_version_rows':stats['max_version_rows'],'max_sql_bytes':stats['max_sql_bytes'],'max_observed_memory_growth_bytes':stats['max_observed_memory_growth_bytes']}),flush=True)
