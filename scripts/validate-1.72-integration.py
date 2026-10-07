#!/usr/bin/env python3
"""Verify integration against accepted crop and released Off outputs; no install."""
from pathlib import Path
import os,json,subprocess,hashlib,datetime,shutil,plistlib,importlib.util
R=Path(__file__).resolve().parent.parent;state=R/'build/integration/1.72';state.mkdir(parents=True,exist_ok=True)
print("1.72 integration validator v2 — accepts insignificant floating-point variance",flush=True)
if subprocess.run(['pgrep','-x','Resolve'],stdout=subprocess.DEVNULL).returncode==0:raise SystemExit('Quit Resolve before integrated validation.')
subprocess.run(['make','version-check','ofx','build/ldb-control-layout-tests','build/ldb-factory-preset-review','build/ldb-optics-tests'],cwd=R,check=True)
for cmd in [['/usr/bin/python3','scripts/check-control-layout.py'],['build/ldb-control-layout-tests']]:subprocess.run(cmd,cwd=R,check=True)
spec=importlib.util.spec_from_file_location('review',R/'scripts/review-new-creative-1.70.py');mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
accepted=R/'build/experiments/final-framing-approved/LDBOptics.metallib';new=R/'build/LDBOptics.metallib';renderer=R/'build/ldb-factory-preset-review'
oldPass=Path((R/'build/integration/1.70/latest-validation-path.txt').read_text().strip());released=next(oldPass.glob('**/LensDebaser.ofx.bundle/Contents/Resources/LDBOptics.metallib'))
report=state/'validation-working';report.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
approval=json.loads((state/'candidate-acceptance.json').read_text());assert approval['shader_sha256']==sha(accepted),'Accepted candidate changed'
env=dict(os.environ)
for k in list(env):
 if k.startswith('LDB_REVIEW_'):env.pop(k)
env.update(LDB_REVIEW_WIDTH='960',LDB_REVIEW_RENDER_ONLY='1')
checks=[]
for name,library,recipe,width in [
 ('accepted-auto-strong-4k',accepted,R/'outputs/experiments/final-framing-working/02-Strong-Inward-Warp-auto.ldbpreset',3840),
 ('accepted-auto-extreme',accepted,R/'outputs/experiments/final-framing-working/03-Extreme-Projection-auto.ldbpreset',960),
 ('released-off-field-focus',released,R/'presets/cinematic-lenses/26-Internal-Field-Edge-FX.ldbpreset',960),
 ('released-off-wide-angle',released,R/'presets/cinematic-lenses/29-Natural-Wide-Angle-2-Medium.ldbpreset',960)]:
 if not recipe.exists():raise SystemExit(f'Missing validation recipe: {recipe}')
 key=sha(library)+sha(new)+sha(renderer)+sha(recipe)+str(width);proof=report/(name+'-proof.json');prefix=report/name
 if not(proof.exists() and json.loads(proof.read_text())['key']==key):
  available,_=mod.available_memory()
  if available<4*1024**3:raise SystemExit('Stopped before next integrated case: less than 4GiB available; completed cases retained.')
  print('Integrated output check:',name,flush=True)
  # Paired single-output audit produces metrics only when bounded timing is requested.
  e=dict(env,LDB_REVIEW_WIDTH=str(width));e.pop('LDB_REVIEW_RENDER_ONLY');e.update(LDB_REVIEW_BENCHMARK_FRAMES='1',LDB_REVIEW_BENCHMARK_RUNS='1')
  with (report/(name+'-log.txt')).open('w') as log:subprocess.run([str(renderer),str(library),str(new),str(R),str(recipe),str(recipe),'milano1',str(prefix)],cwd=R,env=e,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=180)
  result=json.loads(Path(str(prefix)+'-metrics.json').read_text());assert result['nonfinite']==0,f'{name} nonfinite output'
  if name.startswith('accepted-'):assert result['mae']==0,f'{name} changed accepted output'
  else:
   assert result['max_error']<=1e-6,f'{name} exceeds numerical compatibility bound'
   assert Path(str(prefix)+'-before.png').read_bytes()==Path(str(prefix)+'-after.png').read_bytes(),f'{name} changed displayed output'
  proof.write_text(json.dumps({'key':key,'mae':result['mae'],'max_error':result.get('max_error',0),'nonfinite':0,'width':width},indent=2))
 checks.append(name)
for label,library in [('released-1.70',released),('integrated-1.72',new)]:
 key=sha(R/'build/ldb-optics-tests')+sha(library);engineProof=report/(label+'-engine-tests-key.txt')
 if not(engineProof.exists() and engineProof.read_text()==key):
  print(label+' engine regressions (legacy fixed-pixel fixtures)',flush=True)
  with (report/(label+'-engine-tests.txt')).open('w') as log:subprocess.run([str(R/'build/ldb-optics-tests'),str(library)],cwd=R,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=180)
  engineProof.write_text(key)
# Freeze the exact validated normal bundle and factory inputs. Human approval is
# the user's explicit candidate pass plus approval of measured crop overhead;
# this gate requires identical integrated output rather than new visual retuning.
fpTool=R/'scripts/projection-candidate-fingerprint.py'
fp=lambda p:subprocess.check_output(['/usr/bin/python3',str(fpTool),str(p)],text=True).strip()
stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f');snapshot=state/'passed-inputs'/stamp;snapshot.mkdir(parents=True)
staging=Path(__import__('tempfile').mkdtemp(prefix='ldb-171-',dir='/private/tmp'));signed=staging/'LensDebaser.ofx.bundle'
subprocess.run(['ditto','--norsrc','--noextattr',str(R/'build/LensDebaser.ofx.bundle'),str(signed)],check=True)
subprocess.run(['xattr','-cr',str(signed)],check=True);subprocess.run(['codesign','--force','--deep','--sign','-',str(signed)],check=True);subprocess.run(['codesign','--verify','--deep','--strict',str(signed)],check=True)
bundle=snapshot/'LensDebaser.ofx.bundle';subprocess.run(['ditto','--norsrc','--noextattr',str(signed),str(bundle)],check=True)
factory=snapshot/'FactoryPresets';factory.mkdir()
for d in ['demonstrations','cinematic-lenses']:shutil.copytree(R/'presets'/d,factory/d)
shutil.copy2(R/'presets/README.md',factory/'README.md')
info=plistlib.loads((bundle/'Contents/Info.plist').read_bytes());assert info['CFBundleShortVersionString']=='1.72' and info['CFBundleVersion']=='172'
record={'version':'1.72','release_candidate':1,'build':172,'accepted_at':stamp,'acceptance':'User passed crop visuals/UI and approved remaining cost; integrated output exact-match gate passed','bundle':str(bundle),'bundle_fingerprint':fp(bundle),'current_build_fingerprint':fp(R/'build/LensDebaser.ofx.bundle'),'factory':str(factory),'factory_fingerprint':fp(factory),'accepted_shader_sha256':sha(accepted),'integrated_shader_sha256':sha(new),'checks':checks,'report':str(report)}
(state/'passed-build.json').write_text(json.dumps(record,indent=2)+'\n')
print('PASS: normal 1.72 RC1 matches accepted crop and released Off; engine regressions passed. make deploy can install this exact snapshot.')
