#!/usr/bin/env python3
"""Isolated native-resolution comparison in the established swipe layout."""
from pathlib import Path
import struct,sys,html
root=Path(sys.argv[1]);repo=Path(__file__).resolve().parent.parent
style=(repo/'outputs/experiments/field-psf-layer-1/index.html').read_text().split('<style>',1)[1].split('</style>',1)[0]
def size(path):
 data=path.read_bytes()[:24]
 if data[:8]!=b'\x89PNG\r\n\x1a\n':raise SystemExit(f'Invalid PNG: {path}')
 return struct.unpack('>II',data[16:24])
cards=[];rows=[]
for key,label in [('960','960px source → 960px output'),('native','Native 4K source → native 4K output')]:
 a=f'images/{key}-baseline.png';b=f'images/{key}-projection.png'
 dimensions=size(root/a)
 if dimensions!=size(root/b):raise SystemExit('Mismatched dimensions')
 if key=='960' and dimensions!=(960,455):raise SystemExit('Expected existing 960 × 455 images')
 if key=='native' and dimensions!=(4224,2000):raise SystemExit('Expected native 4224 × 2000 images')
 rows.append(f'<tr><th>{label}</th><td>{dimensions[0]} × {dimensions[1]}</td><td>{"Reused validated outputs" if key=="960" else "Two new native renders; finite components checked"}</td></tr>')
 for detail in [False,True]:
  title=label+(' · centre detail at 100%' if detail else ' · full composition')
  cards.append(f'''<article class="{'detail' if detail else ''}"><h2>{title}</h2><p>{'Centre crop: one image pixel per CSS pixel. Compare within this pair; these crops cover different scene areas because the resolutions differ.' if detail else 'Fitted to page width; use the 100% centre detail below to assess sharpness.'}</p><div class="compare" style="--split:50%"><img src="{b}" alt="Projection 20%"><div class="current"><img src="{a}" alt="Projection Off"></div><span class="divider"></span><span class="label left">Projection Off</span><span class="label right">Equidistant 20%</span><input type="range" min="0" max="100" value="50" aria-label="Compare projection off and on"></div></article>''')
log=(root/'render-log.txt').read_text()
if log.count('PASS:')!=2 or 'Nonfinite' in log:raise SystemExit('Native render audit missing or failed')
extra='article p{line-height:1.5}.detail .compare{height:320px;max-width:480px;margin:auto}.detail .compare>img,.detail .current img{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);width:auto;height:auto;max-width:none}.detail .current{width:100%;height:100%}'
doc='<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Projection resolution comparison</title><style>'+style+extra+'</style><body><header><p>ISOLATED RESOLUTION TEST</p><h1>Projection<br>sharpness comparison</h1><p>Equidistant · Amount 20% · 55° · Balanced — iPhone scene 1.</p><p>The 960px pair uses the current validated test outputs. The native pair applies the same projection to the original 4224 × 2000 source, without first reducing it. Both use the same display conversion. No optical blur or sharpening is added.</p><p>Swipe left/right to compare Projection Off with projection applied. Centre details are shown at 100%; browser zoom should be 100%. Native rendering can distinguish preview resolution loss from interpolation softness; this is not a Resolve playback test.</p></header><main>'+''.join(cards)+'<section class="benchmark"><h2>Validation and source resolution</h2><table><thead><tr><th>Comparison</th><th>Output dimensions</th><th>Validation</th></tr></thead><tbody>'+''.join(rows)+'</tbody></table><p>Only two new images rendered. The validated candidate shader is reused. No engine changes or new performance claims.</p></section></main><script>document.querySelectorAll(".compare").forEach(box=>{const input=box.querySelector("input");input.addEventListener("input",()=>box.style.setProperty("--split",input.value+"%"))});</script></body></html>'
(root/'index.html').write_text(doc)
print(f'Built {root}/index.html: two resolution pairs and two 100% centre comparisons')
