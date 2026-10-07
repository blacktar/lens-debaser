#!/usr/bin/env python3
from pathlib import Path
import csv,sys,json,re,statistics
root=Path(sys.argv[1]);baseline=Path(sys.argv[2])
angles=[0,1,5,15,35,55,75,82,85,88,89]
sources=['iso','optical','milano1','milano2','milano3']
expected=[]
for a in angles:
 for m in ['equidistant','stereographic']:
  for f in range(3):
   for s in [20,45,100]:
    if s!=100 and a not in [1,82,89]:continue
    for k in ['geometry','optical']:
     for source in sources:expected.append(f'{m}-a{a}-f{f}-s{s}-{k}-{source}.png')
for name in expected:
 if not (root/'images'/name).is_file():raise SystemExit(f'Missing render: {name}')
rows=list(csv.DictReader((root/'render-audit.csv').open()))
assert len(rows)==len(expected)==1020
assert {r['image'] for r in rows}==set(expected)
invalid=sum(int(r['nonfinite_components']) for r in rows)
zero_error=max(float(r['zero_limit_max_error']) for r in rows)
assert zero_error<=1e-6,f'Zero-angle identity failure: {zero_error}'
mapping=list(csv.DictReader((root/'mapping-audit.csv').open()))
bench={}
for path in sorted(root.glob('benchmark-*.txt')):
 values={name:(float(gpu),float(wall)) for name,gpu,wall in re.findall(r'^(\S+)\s+GPU\s+([0-9.]+) ms\s+wall\s+([0-9.]+) ms',path.read_text(),re.M)}
 for name,b in values.items():
  if name.endswith('-base') and name[:-5]+'-test' in values:
   key=name[:-5];t=values[key+'-test'];bench.setdefault(key,[]).append((b[0],t[0],(t[0]/b[0]-1)*100,b[1],t[1],(t[1]/b[1]-1)*100))
framing_labels=['Full frame','Balanced','Centre scale']
benchmark_rows=[]
for name,values in bench.items():
 m,a,f=re.fullmatch(r'(equidistant|stereographic)-a(\d+)-f(\d+)',name).groups()
 changes=[v[2] for v in values]
 gpu_change=statistics.median(changes);wall_change=statistics.median(v[5] for v in values)
 def color(delta):return 'cost' if delta>2 else 'gain' if delta<-2 else 'neutral'
 benchmark_rows.append(f'<tr><th>{m.capitalize()} · {a}° · {framing_labels[int(f)]}</th><td>{statistics.median(v[0] for v in values):.3f} ms</td><td>{statistics.median(v[1] for v in values):.3f} ms</td><td class="{color(gpu_change)}">{gpu_change:+.1f}%</td><td>{statistics.median(v[3] for v in values):.3f} ms</td><td>{statistics.median(v[4] for v in values):.3f} ms</td><td class="{color(wall_change)}">{wall_change:+.1f}%</td><td>{min(changes):+.1f}% to {max(changes):+.1f}%</td></tr>')
benchmark_html=('<section class="benchmark"><h2>Performance comparison</h2><p>Apple M1 · 1920×1080 · 64 measured frames per case · geometry only. GPU and wall times are medians across three runs; change is the median of paired changes. Baseline runs first. Variability and changed sampling locality prevent treating negative changes as proven speedups. Resolve playback and the full optical recipe are untested.</p><div style="overflow:auto"><table><thead><tr><th>Case</th><th>Current GPU</th><th>Candidate GPU</th><th>GPU change</th><th>Current wall</th><th>Candidate wall</th><th>Wall change</th><th>GPU change range</th></tr></thead><tbody>'+''.join(benchmark_rows)+'</tbody></table></div></section>') if bench else '<section class="benchmark"><h2>Performance comparison</h2><p>Benchmarks have not completed for this pass.</p></section>'
validation_html=f'<section class="benchmark"><h2>Validation results</h2><table><tr><th>Check</th><th>Result</th></tr><tr><th>Completed image cases</th><td>{len(rows):,}</td></tr><tr><th>Invalid linear-render values</th><td>{invalid}</td></tr><tr><th>Largest zero-angle identity difference</th><td>{zero_error:.9g} (pass limit: 0.000001)</td></tr></table><p>Zero-angle identity uses the same sampling path. Mapping calculations use a centered axis and double precision. Finite values do not establish usable framing or approval for release.</p></section>'
# Reuse the established PSF comparison stylesheet, including natural image aspect and on-image labels.
style=(baseline.parent/'field-psf-layer-1/index.html').read_text().split('<style>',1)[1].split('</style>',1)[0]
html='''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Lens Debaser angle limits</title><style>STYLE select{font:inherit;padding:8px;margin:6px;background:#17272d;color:white}summary{cursor:pointer}</style><header><p class="eyebrow">ISOLATED ANGLE-LIMITS EXPERIMENT</p><h1>Field angle limits</h1><p>Degrees from the optical axis to a frame corner. New experiment accepts 0°–89° and removes the former 88° inverse-angle cap. Zero degrees uses the identity limit. Original experiments and release are preserved.</p><p>100% Amount tests every angle; 20% and 45% are available at 1°, 82°, 89°. Compare framing modes, then inspect each candidate against the reused baseline. Numerical finiteness does not establish usable edges, creative quality or Resolve performance. Optical axis is centered in these renders.</p><p>1020 renders verified. Zero-angle identity checks passed within 1e-6 against a reference using the same sampling path. Neutral source-copy and forced resampling may differ slightly. Nonfinite linear-render components: INVALID. Outside-source coordinates can remain finite and yield clamped streaks; inspect the perimeter.</p>
<label>Angle <select id="angle">ANGLES</select></label><label>Amount <select id="strength"><option value="100">100%</option><option value="20">20%</option><option value="45">45%</option></select></label><label>Source <select id="source">SOURCES</select></label></header><main><section class="benchmark"><h2>Mapping for the selected comparison</h2><div id="mapping"></div></section><div id="cards"></div>VALIDATIONBENCHMARK</main><script>
const mappingData=MAPPINGDATA;
const angle=document.querySelector('#angle'),strength=document.querySelector('#strength'),source=document.querySelector('#source'),cards=document.querySelector('#cards');
function pair(a,b,left,right){return `<div class="compare" style="--split:50%"><img src="${b}" alt="${right}" loading="lazy" decoding="async"><div class="current"><img src="${a}" alt="${left}" loading="lazy" decoding="async"></div><span class="divider" aria-hidden="true"></span><span class="label left">${left}</span><span class="label right">${right}</span><input type="range" min="0" max="100" value="50" aria-label="Compare ${left} and ${right}"></div>`}
function update(){const a=angle.value;const limited=![1,82,89].includes(Number(a));for(const o of strength.options)o.disabled=limited&&o.value!=='100';if(limited)strength.value='100';const s=strength.value,src=source.value;let h='';for(const kind of ['geometry','optical']){h+=`<section><h2>${kind==='geometry'?'Geometry only':'Projection-aware optics'}</h2>`;for(const [f,label] of ['Preserve full frame','Balanced','Preserve centre scale'].entries()){const img=m=>`images/${m}-a${a}-f${f}-s${s}-${kind}-${src}.png`;const sourceLabel={iso:'ISO 12233 chart',optical:'LDB synthetic optical chart',milano1:'iPhone scene 1',milano2:'iPhone scene 2',milano3:'iPhone scene 3'}[src];for(const m of ['equidistant','stereographic']){const modelLabel=m==='equidistant'?'Equidistant':'Stereographic';h+=`<article><h2>${modelLabel} · ${label} · ${a}° · Amount ${s}% — ${sourceLabel}</h2>`+pair(`images/baseline-${kind}-${src}.png`,img(m),'Released baseline',modelLabel+' candidate')+'</article>'}h+=`<article><h2>Model comparison · ${label} · ${a}° · Amount ${s}% — ${sourceLabel}</h2>`+pair(img('equidistant'),img('stereographic'),'Equidistant','Stereographic')+'</article>'}h+='</section>'}cards.innerHTML=h;const aspect=src.startsWith('milano')?960/455:960/540;const selected=mappingData.filter(r=>Number(r.angle_degrees)===Number(a)&&Math.abs(Number(r.blend)-Number(s)/100)<1e-6&&Math.abs(Number(r.aspect)-aspect)<1e-6);document.querySelector('#mapping').innerHTML='<div style="overflow:auto"><table><tr><th>Model</th><th>Framing</th><th>Samples outside source</th><th>Largest displacement</th></tr>'+selected.map(r=>`<tr><th>${r.model}</th><td>${r.framing}</td><td>${Number(r.outside_source_percent).toFixed(1)}%</td><td>${(Number(r.max_uv_displacement)*100).toFixed(1)}% of normalized image coordinates</td></tr>`).join('')+'</table></div><p>Outside-source percentage uses a regular coordinate grid, not the fraction of invalid rendered pixels. The sampler can clamp those coordinates to the source boundary, causing visible stretching. Displacement measures distance in normalized image coordinates.</p>';cards.querySelectorAll('.compare').forEach(c=>c.querySelector('input').addEventListener('input',e=>c.style.setProperty('--split',e.target.value+'%')))}
[angle,strength,source].forEach(c=>c.addEventListener('change',update));update();
</script></html>'''
html=html.replace('VALIDATIONBENCHMARK',validation_html+benchmark_html).replace('MAPPINGDATA',json.dumps(mapping)).replace('STYLE',style).replace('INVALID',str(invalid)).replace('ANGLES',''.join(f'<option value="{a}" {"selected" if a==55 else ""}>{a}°</option>' for a in angles)).replace('SOURCES',''.join(f'<option value="{s}">{s}</option>' for s in sources))
(root/'index.html').write_text(html)
print(f'Wrote {root}/index.html; {len(expected)} images; {invalid} nonfinite components')
if invalid:raise SystemExit('FAIL: nonfinite render components; report retained for diagnosis')
