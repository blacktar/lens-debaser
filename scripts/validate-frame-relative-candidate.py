#!/usr/bin/env python3
from pathlib import Path
import datetime,html,json,os,re,shutil,subprocess
repo=Path(__file__).resolve().parent.parent
if subprocess.run(['pgrep','-x','Resolve'],stdout=subprocess.DEVNULL).returncode==0:raise SystemExit('Quit Resolve before isolated rendering.')
vm=subprocess.check_output(['vm_stat'],text=True);page=int(re.search(r'page size of (\d+) bytes',vm).group(1));counts={k:int(v) for k,v in re.findall(r'^([^:]+):\s+(\d+)\.',vm,re.M)}
if sum(counts.get(k,0) for k in ('Pages free','Pages inactive','Pages speculative'))*page<3*1024**3:raise SystemExit('Stopped: less than 3 GiB available/inactive memory; no rendering started.')
state=Path((repo/'build/integration/1.70/latest-frame-relative-candidate-path.txt').read_text().strip())
out=repo/'outputs/experiments'/('frame-relative-validation-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'));(out/'images').mkdir(parents=True)
recipe=repo/'presets/experiments/cinematic-strength-regression-1.70/baseline/cinematic-lenses/26-Internal-Field-Edge-FX.ldbpreset';shutil.copy2(recipe,out/'preset-26.ldbpreset')
shutil.copy2(state/'LDBOptics.metallib',out/'candidate.metallib');shutil.copy2('/Library/OFX/Plugins/LensDebaser.ofx.bundle/Contents/Resources/LDBOptics.metallib',out/'baseline.metallib')
for key,width,tool,library in [('baseline-960',960,repo/'build/ldb-factory-preset-review',out/'baseline.metallib')]+[(f'candidate-{w}',w,state/'renderer',out/'candidate.metallib') for w in (960,1920,3840)]:
 print('One frame:',key,flush=True);prefix=out/'images'/key
 with (out/(key+'-render.txt')).open('w') as log:
  subprocess.run([str(tool),str(library),str(library),str(repo),str(out/'preset-26.ldbpreset'),str(out/'preset-26.ldbpreset'),'iso',str(prefix)],cwd=repo,env=dict(os.environ,LDB_REVIEW_WIDTH=str(width),LDB_REVIEW_SINGLE_RENDER='1',LDB_REVIEW_RENDER_ONLY='1'),stdout=log,stderr=subprocess.STDOUT,timeout=180,check=True)
 assert json.loads(Path(str(prefix)+'-render-audit.json').read_text())['nonfinite']==0
# Exact reference-size preservation is required before accepting this experiment.
identical=(out/'images/baseline-960-before.png').read_bytes()==(out/'images/candidate-960-before.png').read_bytes()
source=(repo/'scripts/build-optical-drift-preset-report.py').read_text();css=source.split('<style>',1)[1].split('</style>',1)[0].replace('{{','{').replace('}}','}')
cards=[]
for w in (960,1920,3840):
 before=(out/'images/baseline-960-before.png').as_uri();after=(out/'images'/f'candidate-{w}-before.png').as_uri()
 cards.append(f'<article><h2>Reference 960 × 540 versus candidate {w} × {w*9//16}</h2><div class="compare"><img src="{after}"><div class="before"><img src="{before}"></div><span class="divider"></span><span class="label left">Current engine · 960 reference</span><span class="label right">Frame Relative Test · {w}px</span><input type="range" min="0" max="100" value="50" aria-label="Compare relative effect strength"></div></article>')
doc='<!doctype html><meta charset="utf-8"><title>Frame-relative candidate</title><style>'+css+'</style><header><h1>Frame Relative Test · original preset 26</h1><p>Fixed display size compares relative effect strength. Three resolutions, four single renders total; finite components passed. No benchmarks. Original presets unchanged. Height sets the optical footprint relative to 540px; host render scale is not multiplied again.</p><p>960 reference file identity: '+('PASS' if identical else 'DIFFERS — investigate before acceptance')+'</p><table><tr><th>Frame</th><th>Scale</th><th>Aperture radius</th></tr><tr><td>960 × 540</td><td>1×</td><td>27 px</td></tr><tr><td>1920 × 1080</td><td>2×</td><td>54 px</td></tr><tr><td>3840 × 2160</td><td>4×</td><td>108 px</td></tr></table><p>Visual acceptance pending. Sampling and input resampling can still differ between resolutions; assess blur extent and protected centre.</p></header><main>'+''.join(cards)+'</main><script>document.querySelectorAll(".compare").forEach(b=>{const i=b.querySelector("input"),l=b.querySelector(".before"),d=b.querySelector(".divider");const f=()=>{l.style.clipPath=`inset(0 ${100-i.value}% 0 0)`;d.style.left=i.value+"%"};i.addEventListener("input",f);f()})</script>'
(out/'index.html').write_text(doc)
report=Path('/Users/blacktar/Documents/Codex/2026-10-04/continue-the-lens-debaser-project-from/outputs/Lens-Debaser-Frame-Relative-Test.html');report.write_text(doc)
(out/'validation.json').write_text(json.dumps({'reference_png_identical':identical,'nonfinite':0,'visual_accepted':False,'benchmark_performed':False}))
subprocess.run(['open',str(report)],check=True)
print('Visual review:',report)
if not identical:raise SystemExit('Reference-size identity differs. No acceptance.')
