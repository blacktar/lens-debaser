#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path(sys.argv[1])
models=['equidistant','stereographic']
sources=['iso','optical','milano1','milano2','milano3']
style=(root/'45/index.html').read_text().split('<style>',1)[1].split('</style>',1)[0]
cards=[]
for kind in ['geometry','optical']:
 cards.append(f'<section><h2>{kind.capitalize()}</h2>')
 for source in sources:
  cards.append(f'<article><h3>{source}</h3>')
  for amount in [20,45,70]:
   a=f'{amount}/images/equidistant-{kind}-{source}.png';b=f'{amount}/images/stereographic-{kind}-{source}.png'
   baseline=root/f'45/images/baseline-{kind}-{source}.png'
   assert (root/a).is_file() and (root/b).is_file(),f'Missing render: {a} or {b}'
   for path in [a,b]:
    assert (root/path).read_bytes()!=baseline.read_bytes(),f'Unchanged candidate: {path}'
   cards.append(f'<h4>{amount}% blend · equidistant / stereographic</h4><div class="compare" style="--split:50%"><img src="{a}" alt="Equidistant"><div class="after"><img src="{b}" alt="Stereographic"></div><span class="line"></span><input type="range" min="0" max="100" value="50" aria-label="Comparison position"></div><p>Left: equidistant · Right: stereographic</p>')
  cards.append('<details><summary>All strengths and baseline</summary><div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px">')
  for model in models:
   cards.append(f'<div><h4>{model}</h4><p>Released baseline</p><img style="width:100%" src="45/images/baseline-{kind}-{source}.png" alt="Baseline">')
   for amount in [20,45,70]:cards.append(f'<p>{amount}% blend</p><img style="width:100%" src="{amount}/images/{model}-{kind}-{source}.png" alt="{model} {amount}%">')
   cards.append('</div>')
  cards.append('</div></details></article>')
 cards.append('</section>')
(root/'index.html').write_text('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Lens Debaser strength sweep</title><style>'+style+'</style><header><p class="eyebrow">NON-PROMOTED EXPERIMENT</p><h1>Projection strength</h1><p>20%, 45% and 70% blend. Both models use 55° half-diagonal angle and balanced framing (0.55). Completed 45% images are reused. Inspect geometry then optics; expand each source to see all strengths and the baseline. Performance logs are separate, using five runs of 64 frames per baseline/candidate case at 1920×1080; geometry only.</p></header><main>'+''.join(cards)+'</main><script>document.querySelectorAll(".compare").forEach(c=>c.querySelector("input").addEventListener("input",e=>c.style.setProperty("--split",e.target.value+"%")))</script></html>')
print(f'Wrote {root}/index.html')
