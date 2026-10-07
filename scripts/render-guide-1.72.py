#!/usr/bin/env python3
"""Complete all strengths in the guide, preserving approved matching pictures."""
from pathlib import Path
import os,subprocess,json,hashlib,shutil,re,importlib.util
r=Path(__file__).resolve().parents[1];dest=r/'docs/user-guide/images/examples';work=r/'outputs/experiments/guide-1.72-all-strengths';work.mkdir(parents=True,exist_ok=True)
spec=importlib.util.spec_from_file_location('creative_memory',r/'scripts/review-new-creative-1.70.py');memory=importlib.util.module_from_spec(spec);spec.loader.exec_module(memory)
lib=r/'build/LDBOptics.metallib';tool=r/'build/ldb-factory-preset-review'
# The accepted normal Off path preserves the approved 1.70 optical pictures.
passed=r/'outputs/experiments/passed/cinematic-1.70-20261007'
assert (passed/'acceptance.json').exists()
approved=json.loads((r/'presets/approved-1.70.json').read_text())['files']
def slug(name):return re.sub(r'[^a-z0-9]+','-',name.lower()).strip('-')
reused=rendered=retained=0
for preset in sorted((r/'presets/cinematic-lenses').glob('*.ldbpreset')):
 assert approved['cinematic-lenses/'+preset.name]==preset.read_text(),preset
 for source in ('iso','optical','milano1','milano2','milano3'):
  target=dest/f'preset-{slug(preset.stem)}-{source}-after.png'
  if target.exists():retained+=1;continue
  saved=passed/f'images/cinematic-lenses--{preset.stem}--{source}-after.png'
  if saved.exists():shutil.copyfile(saved,target);reused+=1;continue
  prefix=work/f'{preset.stem}-{source}';image=Path(str(prefix)+'-render.png');audit=Path(str(prefix)+'-render-audit.json');stamp=Path(str(prefix)+'-complete.txt')
  key=hashlib.sha256(tool.read_bytes()+lib.read_bytes()+preset.read_bytes()+source.encode()).hexdigest()
  if not(stamp.exists() and stamp.read_text()==key and image.exists() and audit.exists()):
   available,method=memory.available_memory()
   if available < 1024**3:raise SystemExit(f'Paused before next case: macOS reports less than 1 GiB available ({method}). Completed images retained; rerun to resume.')
   print(f'Rendering {preset.stem} / {source}: one frame, no benchmark',flush=True)
   env=dict({k:v for k,v in os.environ.items() if not k.startswith("LDB_REVIEW_")},LDB_REVIEW_STANDALONE='1',LDB_REVIEW_SINGLE_RENDER='1',LDB_REVIEW_RENDER_ONLY='1',LDB_REVIEW_BENCHMARK_FRAMES='1',LDB_REVIEW_BENCHMARK_RUNS='1')
   with Path(str(prefix)+'-log.txt').open('w') as log:subprocess.run([str(tool),str(lib),str(lib),str(r),str(preset),str(preset),source,str(prefix)],env=env,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=180)
   assert json.loads(audit.read_text())['nonfinite']==0;stamp.write_text(key)
  shutil.copyfile(image,target);rendered+=1
assert all((dest/f'preset-{slug(p.stem)}-{src}-after.png').exists() for p in (r/'presets/cinematic-lenses').glob('*.ldbpreset') for src in ('iso','optical','milano1','milano2','milano3'))
print(f'Cinematic guide: {retained} retained, {reused} reused, {rendered} completed; 88 presets × 5 images.')
