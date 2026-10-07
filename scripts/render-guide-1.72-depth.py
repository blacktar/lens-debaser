#!/usr/bin/env python3
from pathlib import Path
import os,subprocess,json,hashlib,shutil
r=Path(__file__).resolve().parents[1];out=r/'outputs/experiments/guide-1.72-depth';out.mkdir(parents=True,exist_ok=True)
lib=r/'build/LDBOptics.metallib';tool=r/'build/ldb-factory-preset-review'
for n in (44,45):
 preset=next((r/'presets/demonstrations').glob(f'{n}-*.ldbpreset'))
 for source in ('iso','optical','milano1','milano2','milano3'):
  prefix=out/f'{preset.stem}-{source}';key=hashlib.sha256(tool.read_bytes()+lib.read_bytes()+preset.read_bytes()+source.encode()).hexdigest();stamp=Path(str(prefix)+'-complete.txt');image=Path(str(prefix)+'-render.png')
  if not(stamp.exists() and stamp.read_text()==key and image.exists()):
   env=dict({k:v for k,v in os.environ.items() if not k.startswith("LDB_REVIEW_")},LDB_REVIEW_GUIDE_DEPTH='1',LDB_REVIEW_STANDALONE='1',LDB_REVIEW_SINGLE_RENDER='1',LDB_REVIEW_RENDER_ONLY='1',LDB_REVIEW_BENCHMARK_FRAMES='1',LDB_REVIEW_BENCHMARK_RUNS='1')
   print(f'Rendering {preset.stem} / {source}: one frame, no benchmark',flush=True)
   with Path(str(prefix)+'-log.txt').open('w') as log:subprocess.run([str(tool),str(lib),str(lib),str(r),str(preset),str(preset),source,str(prefix)],env=env,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=180)
   assert json.loads(Path(str(prefix)+'-render-audit.json').read_text())['nonfinite']==0
   stamp.write_text(key)
  assert image.exists(),image
  shutil.copyfile(image,r/f'docs/user-guide/images/examples/demo-{preset.stem.lower()}-{source}-after.png')
subprocess.run(['/usr/bin/python3',str(r/'scripts/build-user-guide.py')],check=True)
print('Guide: '+str(r/'docs/user-guide/Lens-Debaser-User-Guide.html'))
