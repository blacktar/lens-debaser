#!/usr/bin/env python3
"""Compare the saved initial crop engine with the cooperative-search candidate."""
from pathlib import Path
import os,json,subprocess,statistics,hashlib,importlib.util,html
R=Path(__file__).resolve().parent.parent
old=R/'build/experiments/final-framing-uncached/LDBOptics.metallib'
new=R/'build/experiments/final-framing-candidate/LDBOptics.metallib'
renderer=new.parent/'renderer'
W=R/'outputs/experiments/final-framing-working'
O=W/'cached-speed-check';O.mkdir(exist_ok=True)
target=R.parent.parent/'2026-10-04/continue-the-lens-debaser-project-from/outputs/Lens-Debaser-Final-Framing-Review.html'
if subprocess.run(['pgrep','-x','Resolve'],stdout=subprocess.DEVNULL).returncode==0:raise SystemExit('Quit Resolve before the bounded speed check.')
for p in (old,new,renderer,target):
 if not p.exists():raise SystemExit(f'Missing prerequisite: {p}')
spec=importlib.util.spec_from_file_location('review',R/'scripts/review-new-creative-1.70.py');mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
env=dict(os.environ);env.pop('LDB_REVIEW_BASELINE_FIXED',None);env.pop('LDB_REVIEW_STANDALONE',None);env.pop('LDB_REVIEW_RENDER_ONLY',None)
env.update(LDB_REVIEW_WIDTH='3840',LDB_REVIEW_BENCHMARK_FRAMES='4',LDB_REVIEW_BENCHMARK_RUNS='2')
lock=W/'render.lock'
try:lock.mkdir()
except FileExistsError:raise SystemExit('A framing job may already be running; check render.lock.')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
try:
 rows=[];panels=[]
 cases=[row for row in json.loads((R/'presets/experiments/final-framing/manifest.json').read_text())['cases'] if row['id'] in ['02-Strong-Inward-Warp','03-Extreme-Projection']]
 for case in cases:
  name=case['id'];recipe=W/(name+'-auto.ldbpreset');prefix=O/name
  metric=Path(str(prefix)+'-metrics.json');proof=Path(str(prefix)+'-key.txt')
  key=sha(old)+sha(new)+sha(renderer)+sha(recipe)
  if not(metric.exists() and proof.exists() and proof.read_text()==key):
   available,_=mod.available_memory()
   if available<3*1024**3:raise SystemExit('Stopped before next case: less than 3GiB available. Completed checks retained.')
   print('Checking uncached versus cached Auto Fill at 4K:',name,flush=True)
   with (O/(name+'-log.txt')).open('w') as log:
    subprocess.run([str(renderer),str(old),str(new),str(R),str(recipe),str(recipe),'milano1',str(prefix)],cwd=R,env=env,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=180)
   proof.write_text(key)
  data=json.loads(metric.read_text());assert data['nonfinite']==0
  med=lambda field:statistics.median(run[field] for run in data['runs'])
  a,b,c,d=[med(field) for field in ('old_gpu','new_gpu','old_wall','new_wall')]
  rows.append(f'<tr><td>{html.escape(name)}</td><td>{a:.3f} → {b:.3f} ms ({b-a:+.3f} ms)</td><td>{c:.3f} → {d:.3f} ms ({d-c:+.3f} ms)</td><td>MAE {data["mae"]:.9g}</td></tr>')
  initial=Path(str(prefix)+'-before.png');after=Path(str(prefix)+'-after.png')
  assert initial.exists() and after.exists()
  panels.append(f'<h3>{html.escape(name)}: uncached / cached</h3><div class="compare"><img src="{after.as_uri()}"><div class="before"><img src="{initial.as_uri()}"></div><div class="compare-divider" aria-hidden="true"></div><input type="range" value="50" aria-label="Initial versus optimized Auto Fill"><span>Uncached Auto Fill</span><b>Cached Auto Fill</b></div>')
 auditPrefix=O/'cache-invalidation'
 auditEnv=dict(env,LDB_REVIEW_WIDTH='960',LDB_REVIEW_CACHE_AUDIT='1')
 recipe=W/'03-Extreme-Projection-auto.ldbpreset'
 print('Checking cached output, changed settings and changed image content at 960px',flush=True)
 with (O/'cache-invalidation-log.txt').open('w') as log:
  subprocess.run([str(renderer),str(old),str(new),str(R),str(recipe),str(recipe),'milano1',str(auditPrefix)],cwd=R,env=auditEnv,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=180)
 audit=json.loads(Path(str(auditPrefix)+'-cache-audit.json').read_text());assert audit['max_error']==0 and audit['nonfinite']==0
 rows.append(f'<tr><td>Cache reuse / settings changes / image changes</td><td colspan="3">{audit["checks"]} comparisons; maximum difference {audit["max_error"]}; all finite</td></tr>')
 section='<section id="cached-speed-check"><h2>Cached crop search: 4K speed and output check</h2><p>Same two demanding recipes, source and 3840×1820 size; uncached versus cached crop search. Warm timings follow four warm-up frames; first-frame search still occurs. Two alternating runs × four timed frames, per-frame cleanup. The uncached engine provides the matching comparison reference. These short checks do not establish sustained playback speed.</p><table><tr><th>Fixture</th><th>GPU</th><th>Wall</th><th>Output difference</th></tr>'+''.join(rows)+'</table>'+''.join(panels)+'</section>'
 page=target.read_text();start=page.find('<section id="cached-speed-check">')
 if start>=0:
  end=page.index('</section>',start)+len('</section>');page=page[:start]+page[end:]
 page=page.replace('<script>',section+'<script>',1)
 target.write_text(page);(W/'index.html').write_text(page)
 print('Review:',target);subprocess.run(['open',str(target)],check=False)
finally:lock.rmdir()
