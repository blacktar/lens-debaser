#!/usr/bin/env python3
from pathlib import Path
import json,html,subprocess,struct
repo=Path(__file__).resolve().parent.parent
pointer=repo/'build/integration/1.70/latest-resolve-audit-path.txt'
if pointer.exists():
 state=Path(pointer.read_text().strip())
else:
 captures=sorted((repo/'outputs/experiments').glob('resolve-parameter-audit-*/resolve-parameters.jsonl'))
 if captures:
  state=max(captures,key=lambda p:p.stat().st_mtime).parent
 else:
  installed=Path('/Library/OFX/Plugins/LensDebaserParameterAudit.ofx.bundle').exists()
  message=('The audit installation has not completed.' if not installed else 'The audit plug-in is installed, but no parameter capture is available.')
  raise SystemExit(message+'\n'+('Quit Resolve and run ./scripts/recover-resolve-parameter-audit.sh' if not installed else 'Use Lens Debaser 1.70 Parameter Audit on the test node, load original preset 26 and view a frame.'))
p=state/'resolve-parameters.jsonl'
if not p.exists():raise SystemExit('No render captured yet. Apply Lens Debaser 1.70 Parameter Audit, load original 26 and view one frame.')
provenance=state/'actual-metal-library-path.txt'
libraries=provenance.read_text().splitlines() if provenance.exists() else []
for library in libraries:print('Actual loaded Metal library:',library)
records=[json.loads(l) for l in p.read_text().splitlines() if l.strip()]
assert records,'No records'
for r in records:
 packet=bytes.fromhex(r['abi_hex'])
 for key,offset in [('astigmatism',68),('radialSmear',88),('tangentialSmear',92)]:r[key]=struct.unpack_from('<f',packet,offset)[0]
fields=['apertureResponse','apertureRadius','opticalDriftAmount','effectBlend','renderPixelScale','workingColorSpace','processingFlags','depthMode','captureInfluence','lookInfluence','cornerSharpnessLoss','astigmatism','fieldCurvature','radialSmear','tangentialSmear','projectionAmount','projectionModel']
expected=dict(apertureResponse=1,apertureRadius=27,opticalDriftAmount=0,effectBlend=1,processingFlags=0,depthMode=0,captureInfluence=0,lookInfluence=0,cornerSharpnessLoss=1.42,astigmatism=.2,fieldCurvature=.72,radialSmear=0,tangentialSmear=.28,projectionAmount=0,projectionModel=0)
last={(r['stage'],r['width'],r['height']):r for r in records};rows=[]
for (stage,width,height),r in sorted(last.items(),key=lambda item:(-item[0][1]*item[0][2],item[0][0])):
 print(stage,r['width'],r['height'])
 for k in fields:
  target=expected.get(k)
  if stage=='engine-effective' and k=='apertureRadius':target=27*r['renderPixelScale']
  verdict='Input/host context' if target is None else ('Matches' if abs(r[k]-target)<1e-5 else 'DIFFERS')
  print(f'  {k}: {r[k]}  {verdict}')
  rows.append(f'<tr><td>{html.escape(stage)} · {width} × {height}</td><td>{k}</td><td>{r[k]}</td><td>{target if target is not None else "Host context"}</td><td>{verdict}</td></tr>')
doc='''<!doctype html><html><head><meta charset="utf-8"><title>Resolve parameter audit</title><style>body{background:#0a0c0e;color:#eee;font:16px system-ui;margin:40px}table{border-collapse:collapse}td,th{padding:9px;border-bottom:1px solid #444;text-align:left}</style></head><body><h1>Resolve parameter audit · preset 26</h1><p>Actual OFX and effective-engine parameters captured by the separate diagnostic identity. Expected values refer to the exact original Internal Field Edge FX recipe. This does not prove the original production node has identical loaded state.</p><table><tr><th>Stage</th><th>Control</th><th>Actual</th><th>Expected</th><th>Result</th></tr>'''+''.join(rows)+'</table></body></html>'
doc=doc.replace('<table><tr>', '<h2>Actual loaded Metal library</h2><p>'+html.escape('; '.join(libraries) if libraries else 'Not captured by this audit build.')+'</p><table><tr>',1)
(state/'index.html').write_text(doc);subprocess.run(['open',str(state/'index.html')],check=True)
print('Captured audit:',state)
