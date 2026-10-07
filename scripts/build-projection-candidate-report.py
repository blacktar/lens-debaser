#!/usr/bin/env python3
"""Focused report using the established field-PSF comparison presentation."""
from pathlib import Path
import html,json,re,statistics,sys
root=Path(sys.argv[1]);repo=Path(__file__).resolve().parent.parent
reference=repo/'outputs/experiments/field-psf-layer-1/index.html'
style=reference.read_text().split('<style>',1)[1].split('</style>',1)[0]
labels={'iso':'ISO 12233 chart','milano1':'iPhone scene 1'}
cards=[]
for preset in sorted((repo/'presets/experiments/projection-resolve-candidate').glob('*.ldbpreset')):
 fields=dict(line.split('=',1) for line in preset.read_text().splitlines() if '=' in line and not line.startswith('#'))
 model='Equidistant' if fields['projectionModel']=='1' else 'Stereographic'
 amount=fields['projectionAmount'];title=f'{model} · Amount {amount}% · 55° · Balanced'
 for source,label in labels.items():
  candidate=f'images/{preset.stem}-{source}.png'
  for before,left,right,heading in [(f'images/baseline-{source}.png','Released baseline','Projection candidate',title),(f'images/passed-{preset.stem}-{source}.png','Reviewed experiment','Resolve candidate',title+' · implementation comparison')]:
   for name in [before,candidate]:
    if not (root/name).is_file():raise SystemExit(f'Missing comparison image: {name}')
   cards.append(f'''<article><h2>{html.escape(heading)} — {label}</h2>
<div class="compare" style="--split:50%"><img src="{candidate}" alt="{right}" loading="lazy" decoding="async"><div class="current"><img src="{before}" alt="{left}" loading="lazy" decoding="async"></div><span class="divider" aria-hidden="true"></span><span class="label left">{left}</span><span class="label right">{right}</span><input type="range" min="0" max="100" value="50" aria-label="Compare {left} and {right}"></div></article>''')
checks=[]
for name in ['projection-tests.txt','engine-tests.txt']:
 path=root/name
 if not path.is_file():raise SystemExit(f'Missing validation log: {name}')
 text=path.read_text()
 if 'FAIL:' in text or 'PASS:' not in text:raise SystemExit(f'Failed/incomplete validation: {name}')
 for line in text.splitlines():
  if line.startswith('PASS:'):checks.append(f'<tr><th>{html.escape(line[5:].strip())}</th><td>Pass</td></tr>')
bench={}
for path in sorted(root.glob('benchmark-*.txt')):
 values={name:(float(g),float(w)) for name,g,w in re.findall(r'^(\S+)\s+GPU\s+([0-9.]+) ms\s+wall\s+([0-9.]+) ms',path.read_text(),re.M)}
 if len(values)!=12:raise SystemExit(f'Incomplete benchmark: {path}')
 for name,b in values.items():
  if name.endswith('-base'):
   key=name[:-5];t=values[key+'-test'];bench.setdefault(key,[]).append((b[0],t[0],(t[0]/b[0]-1)*100,b[1],t[1],(t[1]/b[1]-1)*100))
rows=[]
def color(v):return 'cost' if v>2 else 'gain' if v<-2 else 'neutral'
for key,values in bench.items():
 med=[statistics.median(v[i] for v in values) for i in range(6)]
 rows.append(f'<tr><th>{key.replace("-"," · ")}%</th><td>{med[0]:.3f} ms</td><td>{med[1]:.3f} ms</td><td class="{color(med[2])}">{med[2]:+.1f}%</td><td>{med[3]:.3f} ms</td><td>{med[4]:.3f} ms</td><td class="{color(med[5])}">{med[5]:+.1f}%</td></tr>')
if len(bench)!=6:raise SystemExit('Six benchmark cases required')
document='''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Lens Debaser — Projection Resolve Candidate</title><style>'''+style+'''</style></head><body><header><p>ISOLATED RESOLVE TEST BUILD · VISUAL PASS 103</p><h1>Projection<br>candidate review</h1><p>Six experimental factory examples: equidistant and stereographic at 20%, 45% and 70% Amount, 55° half-diagonal Field Angle and Balanced framing. Only 12 new images are rendered. Baselines and previously reviewed experiment images are reused.</p><p>Projection is Off by default. Controls allow 0–100% Amount, 0°–89° Field Angle and three framing choices. High angles can strongly magnify or stretch the perimeter. Resolve review on moving footage, faces, architecture, playback and preset save/load is still pending.</p><p>For host review, add “Lens Debaser Projection Test” from the LDB group. Load one example from the separate “Lens Debaser Projection Test/Presets” folder in Application Support; the other examples in that folder become available in the Preset menu. Load existing 1.69 presets to compare disabled-projection behavior. This test plug-in has a separate identity and does not replace 1.69 or update existing project nodes.</p></header><main>'''+''.join(cards)+'''<section class="benchmark"><h2>Automated validation</h2><table><thead><tr><th>Check</th><th>Result</th></tr></thead><tbody>'''+''.join(checks)+'''</tbody></table><p>Automated checks and still-image comparisons do not establish Resolve playback or visual sign-off.</p></section><section class="benchmark"><h2>Performance comparison</h2><p>Apple M1 · 1920×1080 · 64 measured frames per case · three runs · geometry only. Times are medians and changes are medians of paired changes. Both sides use the sampling path to isolate projection cost; the released neutral source-copy path is faster. Run order and device load affect timings. Full optical recipes and Resolve playback require host review.</p><table><thead><tr><th>Case</th><th>Current GPU</th><th>Candidate GPU</th><th>GPU change</th><th>Current wall</th><th>Candidate wall</th><th>Wall change</th></tr></thead><tbody>'''+''.join(rows)+'''</tbody></table></section></main><script>document.querySelectorAll('.compare').forEach(box=>{const input=box.querySelector('input');const update=()=>box.style.setProperty('--split',input.value+'%');input.addEventListener('input',update);update()});</script></body></html>'''
if len(sys.argv)>2 and sys.argv[2]=='1.70':
 audit=json.loads((root/'factory-audit.json').read_text())
 if audit['blocking_errors']:raise SystemExit('Factory integration audit has blockers')
 audit_rows=[]
 for entry in audit['presets']:
  if entry['issues']:
   audit_rows.append('<tr><th>'+html.escape(entry['preset'].split('/')[-1].removesuffix('.ldbpreset'))+'</th><td>'+html.escape('; '.join(entry['issues']))+'</td></tr>')
 section='<section class="benchmark"><h2>Factory preset review flags</h2><p>'+str(audit['preset_count'])+' current presets checked. '+str(audit['legacy_issue_presets'])+' byte-identical released 1.69 presets contain values outside documented ranges. They are preserved for compatibility during this integration pass; they have not passed the upcoming 1.70 factory review. New or modified presets must pass strict validation.</p><table><thead><tr><th>Released preset</th><th>Issue to review</th></tr></thead><tbody>'+''.join(audit_rows)+'</tbody></table></section>'
 document=document.replace('</main>',section+'</main>')
 document=document.replace('ISOLATED RESOLVE TEST BUILD · VISUAL PASS 103','INTEGRATED DEVELOPMENT BUILD 1.70 · VISUAL PASS 104')
 document=document.replace('Projection<br>candidate review','1.70 integration<br>review')
 document=document.replace('Projection Resolve Candidate','1.70 Integration')
 document=document.replace('Resolve candidate','1.70 integration')
 document=document.replace('For host review, add “Lens Debaser Projection Test” from the LDB group.','For host review, add “Lens Debaser 1.70” from the LDB group.')
 document=document.replace('This test plug-in has a separate identity and does not replace 1.69 or update existing project nodes.','This development build uses the stable product identity and replaces the installed 1.69 node implementation. Existing projects need regression review. The separate Projection Test can remain installed. Factory-library re-evaluation and public release are pending.')
 document=document.replace('Field Angle and three framing choices','Field Angle and Fill Frame / Balanced / Preserve Centre Scale framing')
(root/'index.html').write_text(document)
print(f'Built {root}/index.html: 24 comparisons, inline validation and six benchmark rows.')
