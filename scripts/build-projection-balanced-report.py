#!/usr/bin/env python3
"""Build the focused balanced-framing comparison from completed Metal renders."""
from pathlib import Path
import shutil
import sys

root = Path(sys.argv[1])
original = Path(sys.argv[2])
sources = [('iso', 'ISO chart'), ('optical', 'Synthetic optical chart'),
           ('milano1', 'Milano 1'), ('milano2', 'Milano 2'), ('milano3', 'Milano 3')]
images = root / 'images'
for source, _ in sources:
    for kind in ('geometry', 'optical'):
        for model in ('equidistant', 'stereographic'):
            candidate = images / f'{model}-{kind}-{source}.png'
            baseline = original / 'images' / f'baseline-{kind}-{source}.png'
            if not candidate.is_file() or not baseline.is_file():
                raise SystemExit(f'Missing image: {candidate} or {baseline}')
            if candidate.read_bytes() == baseline.read_bytes():
                raise SystemExit(f'Candidate is byte-identical to baseline: {candidate}')
# Reuse passed baselines only after every new candidate exists.
for source, _ in sources:
    for kind in ('geometry', 'optical'):
        name = f'baseline-{kind}-{source}.png'
        shutil.copyfile(original / 'images' / name, images / name)

def compare(before, after, left, right):
    return f'''<div class="compare" style="--split:50%"><img src="images/{before}" alt="{left}">
<div class="after"><img src="images/{after}" alt="{right}"></div><span class="line"></span>
<input type="range" min="0" max="100" value="50" aria-label="Comparison position"></div>
<p>Left: {left} · Right: {right}</p>'''

cards = []
for kind, title in [('geometry', 'Geometry only'), ('optical', 'Projection-aware optics')]:
    cards.append(f'<section><h2>{title}</h2>')
    for source, label in sources:
        cards.append(f'<article><h3>{label}: Equidistant vs stereographic</h3>')
        cards.append(compare(f'equidistant-{kind}-{source}.png', f'stereographic-{kind}-{source}.png', 'Equidistant', 'Stereographic'))
        cards.append('<details><summary>Compare each model with the released baseline</summary>')
        for model in ('equidistant', 'stereographic'):
            cards.append(compare(f'baseline-{kind}-{source}.png', f'{model}-{kind}-{source}.png', 'Released baseline', model.capitalize()))
        cards.append('</details></article>')
    cards.append('</section>')
# Retain the established comparison presentation without changing the old report.
style = (original / 'index.html').read_text().split('<style>', 1)[1].split('</style>', 1)[0]
(root / 'index.html').write_text('''<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Lens Debaser — balanced projection comparison</title><style>''' + style + '''</style></head>
<body><header><p class="eyebrow">NON-PROMOTED EXPERIMENT</p><h1>Balanced framing</h1>
<p>Equidistant and stereographic at 55° half-diagonal field angle, 45% blend and 0.55 framing.
Balanced framing interpolates each model's radial normalization between full-frame fitting and centre-scale preservation. It changes centre scale and does not apply the boundary-safe edge taper.
The optical comparisons use the same established softness and chromatic recipe. Baselines are reused from the previous experiment.</p>
<p>Drag each comparison to inspect centre size, architectural curvature and the extreme perimeter. Review geometry first, then optics. This report records still-image comparisons; Resolve validation and visual approval remain pending. No new performance result is claimed.</p></header><main>''' + ''.join(cards) + '''</main>
<script>document.querySelectorAll('.compare').forEach(c=>c.querySelector('input').addEventListener('input',e=>c.style.setProperty('--split',e.target.value+'%')))</script></body></html>''')
print(f"Wrote {root / 'index.html'}")
