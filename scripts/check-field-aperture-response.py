#!/usr/bin/env python3
"""Two controlled pairs, same installed shader, original preset 26 context."""
from pathlib import Path
import datetime, json, os, shutil, subprocess
repo=Path(__file__).resolve().parent.parent
shader=Path('/Library/OFX/Plugins/LensDebaser.ofx.bundle/Contents/Resources/LDBOptics.metallib')
if not shader.is_file():raise SystemExit('Installed Lens Debaser shader not found; no outputs created.')
subprocess.run(['make','build/ldb-factory-preset-review'],cwd=repo,check=True)
out=repo/'outputs/experiments'/('field-aperture-response-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
(out/'images').mkdir(parents=True);(out/'inputs').mkdir()
shutil.copy2(shader,out/'installed.metallib')
original=repo/'presets/experiments/cinematic-strength-regression-1.70/baseline/cinematic-lenses/26-Internal-Field-Edge-FX.ldbpreset'
recipe=original.read_text();rows=[]
for aperture in (0,1):
 key=f'aperture-{aperture}'
 paths=[]
 for edge in (0,2):
  text=recipe.replace('cornerSharpnessLoss=1.42',f'cornerSharpnessLoss={edge}').replace('apertureResponse=1',f'apertureResponse={aperture}')
  path=out/'inputs'/f'{key}-edge-{edge}.ldbpreset';path.write_text(text);paths.append(path)
 rows.append(dict(id=key,label=f'Aperture {"on" if aperture else "off"} · Edge Focus Loss 0 → 2',baseline_engine='1.70',rationale='Exact preset 26 context. Only Edge Focus Loss differs within this pair; aperture state is fixed. Same installed shader on both sides.',decision='isolate field response',changes={'cornerSharpnessLoss':2},warnings=[],status='diagnostic, not accepted'))
 with (out/f'{key}-run.txt').open('w') as log:
  env=dict(os.environ,LDB_REVIEW_WIDTH='3840')
  subprocess.run([str(repo/'build/ldb-factory-preset-review'),str(out/'installed.metallib'),str(out/'installed.metallib'),str(repo),str(paths[0]),str(paths[1]),'iso',str(out/'images'/f'{key}--iso')],cwd=repo,env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
manifest=dict(original_count=2,candidate_count=2,range_revision_count=0,rows=rows,review_context='Controlled aperture interaction diagnostic; no factory retuning.')
(out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
subprocess.run(['/usr/bin/python3',str(repo/'scripts/build-factory-review-report.py'),str(out)],check=True)
p=out/'index.html';html=p.read_text();start=html.index('<header>');end=html.index('</header>',start)+len('</header>')
html=html[:start]+'''<header><h1>Field Focus Loss × Aperture · installed 1.70</h1><p>Two comparisons at 3840 × 2160. Left: Edge Focus Loss 0. Right: Edge Focus Loss 2. Exact original preset 26 otherwise preserved. First pair: aperture off. Second pair: aperture on. Both sides use the installed shader, with full render scale. This checks the reported interaction; it does not attribute the regression to resolution.</p><p>Four output images only, with finite-component checks and three alternating paired timing runs. Inspect peripheral detail at native size. No deployment, preset retuning or acceptance.</p></header>'''+html[end:]
html=html.replace('engine / prior recipe','engine · Edge Focus Loss 0').replace('engine / proposed recipe','engine · Edge Focus Loss 2')
p.write_text(html)
state=repo/'build/integration/1.70';state.mkdir(parents=True,exist_ok=True);(state/'latest-field-aperture-response-path.txt').write_text(str(out)+'\n')
subprocess.run(['open',str(p)],check=True)
print('Diagnostic ready:',p)
