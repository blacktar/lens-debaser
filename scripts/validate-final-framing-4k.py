#!/usr/bin/env python3
"""Small 4K crop validation with same-case Off/Auto paired timings."""
from pathlib import Path
import os,json,subprocess,statistics,hashlib,importlib.util,html
R=Path(__file__).resolve().parent.parent
S=R/'build/experiments/final-framing-candidate';lib=S/'LDBOptics.metallib';renderer=S/'renderer'
W=R/'outputs/experiments/final-framing-working';O=W/'simplified-4k';O.mkdir(exist_ok=True)
target=R.parent.parent/'2026-10-04/continue-the-lens-debaser-project-from/outputs/Lens-Debaser-Final-Framing-Review.html'
if subprocess.run(['pgrep','-x','Resolve'],stdout=subprocess.DEVNULL).returncode==0:raise SystemExit('Quit Resolve before this bounded 4K check.')
spec=importlib.util.spec_from_file_location('review',R/'scripts/review-new-creative-1.70.py');mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
passed=Path((R/'build/integration/1.70/latest-validation-path.txt').read_text().strip());normal=next(passed.glob('**/LensDebaser.ofx.bundle/Contents/Resources/LDBOptics.metallib'))
env=dict(os.environ)
for k in ['LDB_REVIEW_BASELINE_FIXED','LDB_REVIEW_STANDALONE','LDB_REVIEW_RENDER_ONLY','LDB_REVIEW_SINGLE_RENDER']:env.pop(k,None)
env.update(LDB_REVIEW_WIDTH='3840',LDB_REVIEW_BENCHMARK_FRAMES='2',LDB_REVIEW_BENCHMARK_RUNS='2')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
lock=W/'render.lock'
try:lock.mkdir()
except FileExistsError:raise SystemExit('A framing job may already be active; check render.lock.')
def recipe(name,mode,adjust=0,full=False):
 text=(R/'presets/experiments/final-framing'/f'{name}.ldbpreset').read_text()
 text='\n'.join(line for line in text.splitlines() if not line.startswith('finalFraming'))+'\n'
 if full:text=text.replace('projectionFraming=2','projectionFraming=0')
 p=O/f'{name}-{mode}-{adjust}-{int(full)}.ldbpreset';p.write_text(text+f'finalFramingMode={mode}\nfinalCropAdjustment={adjust}\n');return p
try:
 rows=[];panels=[]
 def run(name,oldlib,oldrecipe,newrecipe,width=3840,renderonly=False,exact=False):
  prefix=O/name;metric=Path(str(prefix)+('-render-audit.json' if renderonly else '-metrics.json'));proof=Path(str(prefix)+'-key.txt')
  key=sha(oldlib)+sha(lib)+sha(renderer)+sha(oldrecipe)+sha(newrecipe)+str(width)+str(renderonly)
  if not(metric.exists() and proof.exists() and proof.read_text()==key):
   available,_=mod.available_memory()
   if available<4*1024**3:raise SystemExit('Stopped before next case: less than 4GiB available. Completed cases retained.')
   print('Checking',name,f'{width}px',flush=True);e=dict(env,LDB_REVIEW_WIDTH=str(width))
   if renderonly:e['LDB_REVIEW_RENDER_ONLY']='1'
   with (O/(name+'-log.txt')).open('w') as log:subprocess.run([str(renderer),str(oldlib),str(lib),str(R),str(oldrecipe),str(newrecipe),'milano1',str(prefix)],cwd=R,env=e,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=180)
   proof.write_text(key)
  d=json.loads(metric.read_text());assert d['nonfinite']==0
  if exact:assert d['mae']==0,'Off compatibility changed'
  if not renderonly:
   med=lambda k:statistics.median(r[k] for r in d['runs'])
   a,b,c,dw=[med(k) for k in ['old_gpu','new_gpu','old_wall','new_wall']]
   rows.append(f'<tr><td>{name}</td><td>{a:.3f} → {b:.3f} ms ({b-a:+.3f} ms)</td><td>{c:.3f} → {dw:.3f} ms ({dw-c:+.3f} ms)</td><td>'+('Exact match' if exact else 'Off / Auto Fill')+'</td></tr>')
  before=Path(str(prefix)+'-before.png');after=Path(str(prefix)+'-after.png');assert before.exists() and after.exists()
  if exact:left,right='Released engine · Off','Experimental engine · Off'
  elif not renderonly:left,right='Auto Fill off','Auto Fill on'
  elif name.startswith('Projection-'):left,right='Projection Full Frame','Centre Scale + Auto Fill'
  else:left,right='Auto Fill · adjustment 0%',name.replace('Crop-Adjustment-Auto-1-', 'Auto Fill · adjustment ').replace('Crop-Adjustment-Auto-0-', 'Manual crop · adjustment ')+'%'
  panels.append(f'<h3>{html.escape(name)}</h3><div class="compare"><img src="{after.as_uri()}"><div class="before"><img src="{before.as_uri()}"></div><div class="compare-divider" aria-hidden="true"></div><input type="range" value="50" aria-label="{html.escape(name)}"><span>{html.escape(left)}</span><b>{html.escape(right)}</b></div>')
 strong='02-Strong-Inward-Warp';extreme='03-Extreme-Projection'
 off=recipe(strong,0);run('4K-Off-compatibility',normal,off,off,exact=True)
 for name in [strong,extreme]:run(name+'-4K-Off-versus-Auto',lib,recipe(name,0),recipe(name,1))
 for mode,adjust in [(1,-10),(1,10),(0,25)]:run(f'Crop-Adjustment-Auto-{mode}-{adjust:+d}',lib,recipe(extreme,1),recipe(extreme,mode,adjust),960,True)
 run('Projection-Full-Frame-versus-Final-Auto',lib,recipe(extreme,0,full=True),recipe(extreme,1),960,True)
 section='<section id="simplified-4k"><h2>Simplified controls and 4K check</h2><p>Auto Fill Frame on/off plus Crop Adjustment. Negative adjustment restores more composition and may expose unwanted edges; positive adjustment crops farther. Auto Fill off uses adjustment as manual crop. 4K-width footage keeps its original aspect ratio (3840×1820). Two alternating runs × two timed frames; not sustained playback evidence. Adjustment/Projection Full Frame examples are render-only.</p><table><tr><th>Check</th><th>GPU</th><th>Wall</th><th>Result</th></tr>'+''.join(rows)+'</table>'+''.join(panels)+'</section>'
 page=target.read_text();start=page.find('<section id="simplified-4k">')
 if start>=0:page=page[:start]+page[page.index('</section>',start)+len('</section>'):]
 page=page.replace('<script>',section+'<script>',1);target.write_text(page);(W/'index.html').write_text(page)
 print('Review:',target);subprocess.run(['open',str(target)],check=False)
finally:lock.rmdir()
