#!/usr/bin/env python3
"""Render only missing/changed guide assets; reuse approved footage outputs."""
from pathlib import Path
import argparse,hashlib,json,os,runpy,shutil,subprocess,tempfile,importlib.util
R=Path(__file__).resolve().parent.parent
WORK=R/'outputs/experiments/guide-1.70-working';WORK.mkdir(parents=True,exist_ok=True)
OUT=R/'docs/user-guide/images/examples';OUT.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def values(text):return {k:float(v) for line in text.splitlines() if '=' in line and not line.startswith('#') for k,v in [line.split('=',1)] if k!='LensDebaserPreset'}
def main():
 args=argparse.ArgumentParser();args.add_argument('--prepare-only',action='store_true');opt=args.parse_args()
 guide=runpy.run_path(str(R/'scripts/build-user-guide.py'));jobs={};copied=0
 approved=R/'outputs/experiments/cinematic-footage-20261006-182627-391702/images'
 new=R/'outputs/experiments/new-creative-1.70-working/images'
 for preset in guide['medium_presets']:
  name=preset.stem;slug=guide['guide_file_slug'](name)
  initial=subprocess.run(['git','show','HEAD:presets/cinematic-lenses/'+preset.name],cwd=R,capture_output=True,text=True)
  for source,_ in guide['atlas_sources']:
   destination=OUT/f'preset-{slug}-{source}-after.png'
   if source=='milano1':
    saved=(new/f'new-creative--{name}--milano1-render.png') if name.startswith(('29-','30-','31-','32-')) else approved/f'cinematic-lenses--{name}--milano1-after.png'
    assert saved.is_file(),saved
    if not destination.exists() or sha(destination)!=sha(saved):shutil.copy2(saved,destination);copied+=1
   elif source in ('iso','optical') and initial.returncode==0 and values(initial.stdout)==values(preset.read_text()) and destination.exists():continue
   else:jobs[destination.name]=(preset,source)
 for slug,title,_,_,_ in guide['example_specs']:
  if slug in ('depth','diagnostic-views'):continue # Preserve established depth/diagnostic fixtures.
  number=guide['example_demo_numbers'][slug];preset=next((R/'presets/demonstrations').glob(f'{number:02d}-*.ldbpreset'))
  legacy=subprocess.run(['git','show','HEAD:presets/demonstrations/'+preset.name],cwd=R,capture_output=True,text=True)
  for source,_ in guide['atlas_sources']:
   destination=OUT/f'{slug}-{source}-after.png'
   if source in ('iso','optical') and legacy.returncode==0 and values(legacy.stdout)==values(preset.read_text()) and destination.exists():continue
   jobs[destination.name]=(preset,source)
 # Focused new-feature visuals, two established sources per demonstration.
 for number in range(33,44):
  preset=next((R/'presets/demonstrations').glob(f'{number:02d}-*.ldbpreset'))
  for source in ('iso','milano1'):jobs[f'demo-{preset.stem.lower()}-{source}-after.png']=(preset,source)
 manifest={'jobs':[{'output':name,'preset':str(p.relative_to(R)),'source':source} for name,(p,source) in jobs.items()]}
 (WORK/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');print(f'Reused accepted footage outputs; {len(jobs)} missing/changed guide assets, no benchmarks.',flush=True)
 if opt.prepare_only:return
 if subprocess.run(['pgrep','-x','Resolve'],stdout=subprocess.DEVNULL).returncode==0:raise SystemExit('Quit Resolve before guide renders.')
 subprocess.run(['make','build/ldb-factory-preset-review'],cwd=R,check=True)
 passed=Path((R/'build/integration/1.70/latest-validation-path.txt').read_text().strip());lib=next(passed.glob('**/LensDebaser.ofx.bundle/Contents/Resources/LDBOptics.metallib'))
 assert sha(lib)=='bcbf6925184a21a4ec152a1bec418b4fe1a5d09a8a2ca7f86930cb81a40379d6'
 spec=importlib.util.spec_from_file_location('review',R/'scripts/review-new-creative-1.70.py');review=importlib.util.module_from_spec(spec);spec.loader.exec_module(review)
 env=dict(os.environ);env.pop('LDB_REVIEW_BASELINE_FIXED',None);env.update(LDB_REVIEW_STANDALONE='1',LDB_REVIEW_RENDER_ONLY='1',LDB_REVIEW_WIDTH='960')
 states=json.loads((WORK/'states.json').read_text()) if (WORK/'states.json').exists() else {}
 lock=WORK/'render.lock'
 try:lock.mkdir()
 except FileExistsError:raise SystemExit('Guide render lock exists; check for another active run.')
 try:
  for name,(preset,source) in jobs.items():
   destination=OUT/name;key=sha(preset)+sha(lib)+source+'960-relative-v1'
   if states.get(name)==key and destination.exists():continue
   available,method=review.available_memory()
   if available<3*1024**3:raise SystemExit(f'Stopped: {available/1024**3:.2f}GiB available ({method}); completed cases retained.')
   print('Rendering',name,flush=True)
   with tempfile.TemporaryDirectory(dir=WORK) as temp:
    prefix=Path(temp)/'guide';log=WORK/'last-render-log.txt'
    with log.open('w') as handle:subprocess.run([str(R/'build/ldb-factory-preset-review'),str(lib),str(lib),str(R),str(preset),str(preset),source,str(prefix)],env=env,cwd=R,stdout=handle,stderr=subprocess.STDOUT,timeout=180,check=True)
    audit=json.loads(Path(str(prefix)+'-render-audit.json').read_text());assert audit['nonfinite']==0
    shutil.copy2(Path(str(prefix)+'-render.png'),destination)
   states[name]=key;(WORK/'states.json').write_text(json.dumps(states,indent=2)+'\n')
  subprocess.run(['/usr/bin/python3',str(R/'scripts/build-user-guide.py')],check=True)
  print('Guide render batch complete. Guide still needs visual inspection and final release checks.')
 finally:lock.rmdir()
if __name__=='__main__':main()
