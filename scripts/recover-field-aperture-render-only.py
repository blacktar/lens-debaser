#!/usr/bin/env python3
"""Recover completed work; render only missing aperture-on endpoints."""
from pathlib import Path
import datetime,json,os,re,shutil,subprocess
repo=Path(__file__).resolve().parent.parent
if subprocess.run(['pgrep','-x','Resolve'],stdout=subprocess.DEVNULL).returncode==0:
 raise SystemExit('Quit Resolve before this isolated render to avoid competing GPU/memory workloads.')
vm=subprocess.check_output(['vm_stat'],text=True)
page=int(re.search(r'page size of (\d+) bytes',vm).group(1))
counts={k:int(v) for k,v in re.findall(r'^([^:]+):\s+(\d+)\.',vm,re.M)}
available=sum(counts.get(k,0) for k in ('Pages free','Pages inactive','Pages speculative'))*page
if available<3*1024**3:raise SystemExit('Stopped before rendering: less than 3 GiB free/inactive/speculative memory. No automatic retry.')
prior=repo/'outputs/experiments/field-aperture-response-20261006-104643-296693'
for rel in ('installed.metallib','images/aperture-0--iso-before.png','images/aperture-0--iso-after.png'):
 if not (prior/rel).is_file():raise SystemExit('Missing preserved input: '+rel)
subprocess.run(['make','build/ldb-factory-preset-review'],cwd=repo,check=True)
out=repo/'outputs/experiments'/('field-aperture-render-only-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
(out/'images').mkdir(parents=True);(out/'inputs').mkdir()
shutil.copy2(prior/'installed.metallib',out/'installed.metallib')
for name in ('aperture-0--iso-before.png','aperture-0--iso-after.png'):shutil.copy2(prior/'images'/name,out/'images'/name)
original=(repo/'presets/experiments/cinematic-strength-regression-1.70/baseline/cinematic-lenses/26-Internal-Field-Edge-FX.ldbpreset').read_text()
for edge in (0,2):
 preset=out/'inputs'/f'edge-{edge}.ldbpreset';preset.write_text(original.replace('cornerSharpnessLoss=1.42',f'cornerSharpnessLoss={edge}'))
 prefix=out/'images'/f'aperture-1-edge-{edge}'
 print(f'Rendering aperture on, Edge Focus Loss {edge}: one frame, no benchmark.',flush=True)
 env=dict(os.environ,LDB_REVIEW_WIDTH='3840',LDB_REVIEW_RENDER_ONLY='1',LDB_REVIEW_SINGLE_RENDER='1')
 with (out/f'edge-{edge}-render.txt').open('w') as log:
  subprocess.run([str(repo/'build/ldb-factory-preset-review'),str(out/'installed.metallib'),str(out/'installed.metallib'),str(repo),str(preset),str(preset),'iso',str(prefix)],cwd=repo,env=env,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=180)
 audit=json.loads(Path(str(prefix)+'-render-audit.json').read_text());assert audit['nonfinite']==0
# Preserve established swipe format from the already recovered HTML.
chat=Path('/Users/blacktar/Documents/Codex/2026-10-04/continue-the-lens-debaser-project-from/outputs')
base=(chat/'Lens-Debaser-Recovered-Field-Focus.html').read_text()
start=base.index('<article>');end=base.index('</article>',start)+len('</article>')
old=base[start:end]
for name in ('aperture-0--iso-before.png','aperture-0--iso-after.png'):
 old=old.replace((prior/'images'/name).as_uri(),(out/'images'/name).as_uri())
new=old.replace('Aperture off','Aperture on')
new=new.replace('aperture-0--iso-before.png','aperture-1-edge-0-before.png').replace('aperture-0--iso-after.png','aperture-1-edge-2-before.png')
base=base[:start]+old+new+base[end:]
hs=base.index('<header>');he=base.index('</header>',hs)+len('</header>')
base=base[:hs]+'''<header><h1>Field Focus × Aperture · recovered diagnostic</h1><p>Original preset 26. Left: Edge Focus Loss 0. Right: 2. First pair: aperture off, reused from the interrupted run. Second pair: aperture on, two new single-frame renders in separate processes. Same snapshotted installed 1.70 shader; 3840 × 2160.</p><p>New renders passed finite-component checks. No benchmarks performed. This tests the interaction, not the cause of the Resolve regression. No release acceptance.</p></header>'''+base[he:]
(out/'index.html').write_text(base)
report=chat/'Lens-Debaser-Field-Aperture-Render-Only.html';report.write_text(base)
subprocess.run(['open',str(report)],check=True)
print('Comparison:',report)
