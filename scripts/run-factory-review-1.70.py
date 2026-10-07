#!/usr/bin/env python3
"""Run a focused, immutable review batch in the user's Metal-enabled CLI."""
from pathlib import Path
import datetime,json,shutil,subprocess,sys,os,re
repo=Path(__file__).resolve().parent.parent
plan=Path(os.environ.get('LDB_FACTORY_REVIEW_PLAN',str(repo/'presets/experiments/factory-review-1.70-current-library')))
m=json.loads((plan/'manifest.json').read_text());batch=sys.argv[1] if len(sys.argv)>1 else 'demos'
if batch in m['batches']:selected=set(m['batches'][batch])
else:selected=set(sys.argv[1:])
rows=[r for r in m['rows'] if r['id'] in selected]
assert rows and len(rows)==len(selected),'Unknown batch/preset; inspect the review inventory'
subprocess.run(['make','build/ldb-factory-preset-review'],cwd=repo,check=True)
stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
out=repo/'outputs/experiments'/('factory-review-1.70-'+stamp);(out/'images').mkdir(parents=True)
# Snapshot exact preset and engine inputs before rendering. Prior passes are retained.
shutil.copytree(plan,out/'inputs')
m['batch']=batch;
if os.environ.get('LDB_REVIEW_CURRENT_ENGINE_BASELINE')=='1':
 for row in m['rows']:
  if row['id'] in selected:row['baseline_engine']='1.70'
(out/'manifest.json').write_text(json.dumps(m,indent=2)+'\n')
baseline=Path((repo/'build/integration/1.70/baseline-1.69-path.txt').read_text().strip())/'LensDebaser.ofx.bundle/Contents/Resources/LDBOptics.metallib'
shutil.copy2(baseline,out/'baseline.metallib');shutil.copy2(repo/'build/LDBOptics.metallib',out/'candidate.metallib')
with (out/'run-log.txt').open('w') as log:
 for row in rows:
  for source in ([('iso' if row['label'].startswith(('14-','21-')) else 'milano1')] if os.environ.get('LDB_REVIEW_TARGETED_SOURCES')=='1' else ['iso','milano1']):
   if os.environ.get('LDB_REVIEW_BOUNDED_GUARD')=='1':
    vm=subprocess.check_output(['vm_stat'],text=True)
    page=int(re.search(r'page size of (\d+) bytes',vm).group(1))
    counts={k:int(v) for k,v in re.findall(r'^([^:]+):\s+(\d+)\.',vm,re.M)}
    if sum(counts.get(k,0) for k in ('Pages free','Pages inactive','Pages speculative'))*page<3*1024**3:
     raise SystemExit('Stopped before next render: less than 3 GiB free/inactive memory. Completed outputs preserved.')
   prefix=out/'images'/(row['id']+'--'+source)
   print('Reviewing',row['label'],source,flush=True)
   old=out/'inputs/baseline'/Path(row['baseline']).relative_to(plan.relative_to(repo)/'baseline')
   new=out/'inputs/candidate'/Path(row['candidate']).relative_to(plan.relative_to(repo)/'candidate')
   subprocess.run([str(repo/'build/ldb-factory-preset-review'),str(out/('candidate.metallib' if row.get('baseline_engine')=='1.70' or os.environ.get('LDB_REVIEW_CURRENT_ENGINE_BASELINE')=='1' else 'baseline.metallib')),str(out/'candidate.metallib'),str(repo),str(old),str(new),source,str(prefix)],cwd=repo,stdout=log,stderr=subprocess.STDOUT,timeout=180 if os.environ.get('LDB_REVIEW_BOUNDED_GUARD')=='1' else None,check=True)
subprocess.run(['/usr/bin/python3',str(repo/'scripts/build-factory-review-report.py'),str(out)],check=True)
state=repo/'build/integration/1.70';(state/'latest-factory-review-path.txt').write_text(str(out)+'\n')
subprocess.run(['open',str(out/'index.html')],check=True)
print('Review ready:',out/'index.html','\nNo installation or acceptance performed.')
