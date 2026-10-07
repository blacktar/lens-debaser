#!/usr/bin/env python3
"""Small isolated framing comparison; no legacy regeneration or factory changes."""
from pathlib import Path
import json,os,subprocess,tempfile,hashlib,html,importlib.util
R=Path(__file__).resolve().parent.parent
S=Path((R/'build/integration/1.70/latest-final-framing-candidate-path.txt').read_text().strip())
W=R/'outputs/experiments/final-framing-working';W.mkdir(parents=True,exist_ok=True)
if subprocess.run(['pgrep','-x','Resolve'],stdout=subprocess.DEVNULL).returncode==0:raise SystemExit('Quit Resolve before this small render batch.')
spec=importlib.util.spec_from_file_location('review',R/'scripts/review-new-creative-1.70.py');mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
lib=S/'LDBOptics.metallib';renderer=S/'renderer';plan=R/'presets/experiments/final-framing/manifest.json';cases=json.loads(plan.read_text())['cases']
env=dict(os.environ);env.pop('LDB_REVIEW_BASELINE_FIXED',None);env.update(LDB_REVIEW_WIDTH='960',LDB_REVIEW_STANDALONE='1',LDB_REVIEW_RENDER_ONLY='1')
lock=W/'render.lock'
try:lock.mkdir()
except FileExistsError:raise SystemExit('Another framing render may be active; check render.lock.')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
try:
 panels=[]
 for row in cases:
  original=(plan.parent/row['preset']).read_text();images=[]
  for tag,mode,zoom,margin in [('off',0,100,0),('auto',1,100,0),('manual',2,150,0),('margin',1,100,5)]:
   text=original.replace('finalFramingMode=0',f'finalFramingMode={mode}').replace('finalFramingZoom=100',f'finalFramingZoom={zoom}').replace('finalFramingMargin=0',f'finalFramingMargin={margin}')
   recipe=W/(row['id']+'-'+tag+'.ldbpreset');recipe.write_text(text);prefix=W/(row['id']+'-'+tag);image=Path(str(prefix)+'-render.png');evidence=Path(str(prefix)+'-evidence.json');key=hashlib.sha256((text+sha(lib)+sha(renderer)).encode()).hexdigest()
   if not (image.exists() and evidence.exists() and json.loads(evidence.read_text())['key']==key):
    available,method=mod.available_memory()
    if available<3*1024**3:raise SystemExit(f'Stopped: {available/1024**3:.2f}GiB available; completed cases retained.')
    print('Rendering',row['id'],tag,flush=True)
    with (W/'last-render-log.txt').open('w') as log:subprocess.run([str(renderer),str(lib),str(lib),str(R),str(recipe),str(recipe),'milano1',str(prefix)],cwd=R,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=180,check=True)
    audit=json.loads(Path(str(prefix)+'-render-audit.json').read_text());assert audit['nonfinite']==0
    evidence.write_text(json.dumps({'key':key,'audit':audit},indent=2))
   images.append(image)
  comparisons=[]
  for i,label in enumerate(['Off / Auto Fill','Off / Manual150%','Off / Auto Fill +5% margin'],start=1):
   comparisons.append(f'<h3>{label}</h3><div class="compare"><img src="{images[i].as_uri()}"><div class="before"><img src="{images[0].as_uri()}"></div><div class="compare-divider" aria-hidden="true"></div><input type="range" value="50" aria-label="{label}"><span>Off</span><b>{label.split(" / ")[1]}</b></div>')
  panels.append('<section><h2>'+html.escape(row['id'])+'</h2>'+''.join(comparisons)+'</section>')
 # Two bounded paired checks: exact Off compatibility and framing overhead.
 timings=[]
 passed=Path((R/'build/integration/1.70/latest-validation-path.txt').read_text().strip())
 baseline=next(passed.glob('**/LensDebaser.ofx.bundle/Contents/Resources/LDBOptics.metallib'))
 benchEnv=dict(env);benchEnv.pop('LDB_REVIEW_STANDALONE',None);benchEnv.pop('LDB_REVIEW_RENDER_ONLY',None)
 benchEnv.update(LDB_REVIEW_BENCHMARK_FRAMES='4',LDB_REVIEW_BENCHMARK_RUNS='2')
 for name,oldLib,oldRecipe,newRecipe in [('Off compatibility',baseline,W/'01-Normal-Barrel-off.ldbpreset',W/'01-Normal-Barrel-off.ldbpreset'),('Auto Fill overhead',lib,W/'02-Strong-Inward-Warp-off.ldbpreset',W/'02-Strong-Inward-Warp-auto.ldbpreset')]:
  prefix=W/('benchmark-'+name.replace(' ','-'));metric=Path(str(prefix)+'-metrics.json');proof=Path(str(prefix)+'-key.txt')
  key=sha(oldLib)+sha(lib)+sha(oldRecipe)+sha(newRecipe)+sha(renderer)
  if not (metric.exists() and proof.exists() and proof.read_text()==key):
   available,method=mod.available_memory()
   if available<3*1024**3:raise SystemExit('Stopped before timings; completed images retained.')
   print('Bounded timing:',name,flush=True)
   with (W/'last-benchmark-log.txt').open('w') as log:subprocess.run([str(renderer),str(oldLib),str(lib),str(R),str(oldRecipe),str(newRecipe),'milano1',str(prefix)],cwd=R,env=benchEnv,stdout=log,stderr=subprocess.STDOUT,timeout=180,check=True)
   proof.write_text(key)
  data=json.loads(metric.read_text());assert data['nonfinite']==0
  if name=='Off compatibility':assert data['mae']==0,'Off changed approved1.70 output'
  import statistics
  def med(field):return statistics.median(run[field] for run in data['runs'])
  a,b,c,d=[med(k) for k in ('old_gpu','new_gpu','old_wall','new_wall')]
  timings.append(f'<tr><td>{name}</td><td>{a:.3f} → {b:.3f} ms ({b-a:+.3f} ms)</td><td>{c:.3f} → {d:.3f} ms ({d-c:+.3f} ms)</td><td>'+('Exact match' if name=='Off compatibility' else 'Two alternating runs × four frames; not sustained playback')+'</td></tr>')
 panels.append('<h2>Validation and bounded timings</h2><table><tr><th>Check</th><th>GPU</th><th>Wall</th><th>Scope</th></tr>'+''.join(timings)+'</table>')
 page='''<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Final Framing Experiment</title><style>body{background:#141719;color:#eee;font:16px system-ui;margin:30px auto;max-width:1000px;padding:20px}section{margin:50px 0}.compare{position:relative;aspect-ratio:960/455;overflow:hidden}.compare img{width:100%;height:100%;object-fit:contain}.before{position:absolute;inset:0;width:50%;overflow:hidden}.before img{max-width:none}.compare input{position:absolute;inset:0;width:100%;height:100%;opacity:0;cursor:ew-resize}.compare span,.compare b{position:absolute;top:8px;background:#000a;padding:5px}.compare span{left:8px}.compare b{right:8px}.compare-divider{position:absolute;top:0;bottom:0;left:50%;width:2px;background:#fff;transform:translateX(-1px);pointer-events:none;z-index:2}.compare-divider:after{content:'↔';position:absolute;top:50%;left:50%;display:grid;place-items:center;width:38px;height:38px;border-radius:50%;background:#fff;color:#111;font:800 20px system-ui;transform:translate(-50%,-50%)}.compare input{z-index:3}.compare span,.compare b{z-index:2;pointer-events:none}</style><h1>Final Framing — experimental</h1><p>Five edge-problem fixtures on iPhone scene1; Off versus Auto Fill, Manual150% and Auto Fill +5% Safety Margin. No previous-release baseline. All renders checked finite.</p><p>Auto Fill uses padded source-coordinate coverage on a65×37 grid and searches up to8× zoom. It does not guarantee arbitrary folds, large blur footprints or letterboxing already in the source. Manual can remain insufficient. Judge framing, stretched boundaries, black edges, centre sharpness and loss of composition.</p>'''+''.join(panels)+'''<script>document.querySelectorAll('.compare').forEach(c=>{const b=c.querySelector('.before'),r=c.querySelector('input');const u=()=>{b.style.width=r.value+'%';c.querySelector('.compare-divider').style.left=r.value+'%';b.querySelector('img').style.width=c.clientWidth+'px'};r.addEventListener('input',u);new ResizeObserver(u).observe(c);u()})</script>'''
 target=R.parent.parent/'2026-10-04/continue-the-lens-debaser-project-from/outputs/Lens-Debaser-Final-Framing-Review.html';target.write_text(page);(W/'index.html').write_text(page);print('Review:',target)
 subprocess.run(['open',str(target)],check=False)
finally:lock.rmdir()
