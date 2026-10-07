#!/usr/bin/env python3
"""Prepare isolated full-library review candidates, never rewrite factory files."""
from pathlib import Path
import json,re,subprocess,importlib.util
repo=Path(__file__).resolve().parent.parent
root=repo/'presets/experiments/factory-review-1.70-v1'
if root.exists():raise SystemExit('Review already prepared; preserve it and inspect its manifest.')
schema=json.loads((repo/'preset-authoring/Lens-Debaser-Preset-Schema.json').read_text())
schema['controls'].update({k:dict(type=t,minimum=lo,maximum=hi,default=d) for k,t,lo,hi,d in [('projectionModel','choice',0,2,0),('projectionAmount','float',0,100,0),('projectionFieldAngle','float',0,89,55),('projectionFraming','choice',0,2,1)]})
spec=importlib.util.spec_from_file_location('validator',repo/'scripts/validate-preset.py');v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
def fields(text):return {a:float(b) for line in text.splitlines() if '=' in line and not line.startswith('#') for a,b in [line.split('=',1)] if a!='LensDebaserPreset'}
def patch(text,changes,note=''):
 lines=text.splitlines();seen=set()
 for i,line in enumerate(lines):
  if '=' in line and not line.startswith('#'):
   k=line.split('=',1)[0]
   if k in changes:lines[i]=f'{k}={changes[k]:g}';seen.add(k)
 lines += [f'{k}={val:g}' for k,val in changes.items() if k not in seen]
 if note:lines.insert(1,'# 1.70 review: '+note)
 return '\n'.join(lines)+'\n'
def write(side,rel,text):
 p=root/side/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text);return str(p.relative_to(repo))
rows=[]
for path in sorted([* (repo/'presets/demonstrations').glob('*.ldbpreset'),*(repo/'presets/cinematic-lenses').glob('*.ldbpreset')]):
 rel=path.relative_to(repo/'presets');text=path.read_text();old=subprocess.check_output(['git','show','4bd0dd1:presets/'+str(rel)],cwd=repo,text=True)
 assert text==old,'Factory baseline modified; inspect before preparing: '+str(rel)
 f=fields(text);changes={k:max(schema['controls'][k]['minimum'],min(schema['controls'][k]['maximum'],x)) for k,x in f.items() if x<schema['controls'][k]['minimum'] or x>schema['controls'][k]['maximum']}
 label=path.stem;family=re.sub(r'-[123]-(Subtle|Medium|Caricature)$','',label)
 reason=('Normalize out-of-range authored values to current control bounds; compare against exact released recipe before acceptance.' if changes else 'Retain established character; no projection added merely because the engine supports it.')
 if rel.parts[0]=='demonstrations':reason+=' Educational scope reviewed against the current UI; existing stable control keys retained.'
 elif 'Subtle' in label:reason+=' Keep restrained finishing intent.'
 elif 'Caricature' in label:reason+=' Retain explicitly exaggerated variant; judge as a creative extreme.'
 else:reason+=' Keep usable starting-point intent.'
 row=dict(id=str(rel.with_suffix('')).replace('/','--'),label=label,family=family,decision='revise ranges' if changes else 'keep pending compatibility review',rationale=reason,changes=changes,baseline=write('baseline',rel,old),candidate=write('candidate',rel,patch(text,changes) if changes else text),status='awaiting evidence / user acceptance',warnings=[])
 errors,warnings=v.validate(repo/row['candidate'],schema);assert not errors,errors;row['warnings']=warnings;rows.append(row)
def add(rel,baseline_rel,changes,note):
 base=(root/'candidate'/baseline_rel).read_text() if baseline_rel else 'LensDebaserPreset=2\n'
 text=patch(base,changes,note);row=dict(id=str(rel.with_suffix('')).replace('/','--'),label=rel.stem,family=rel.stem,decision='new demonstration' if rel.parts[0]=='demonstrations' else 'new creative treatment',rationale=note,changes=changes,baseline=write('baseline',rel,base),candidate=write('candidate',rel,text),status='awaiting renders / benchmarks / user acceptance',warnings=[])
 errors,warnings=v.validate(repo/row['candidate'],schema);assert not errors,errors;row['warnings']=warnings;rows.append(row)
projection=dict(projectionModel=1,projectionAmount=45,projectionFieldAngle=55,projectionFraming=1)
for n,title,chg,note in [(33,'Equidistant-Projection',{},'Equidistant at 45%, 55 degrees, Balanced; compare with clean source.'),(34,'Stereographic-Projection',{'projectionModel':2},'Gentler stereographic at matched 45%, 55 degrees, Balanced; compare with clean source.'),(35,'Projection-Centre-Scale',{'projectionFraming':2},'Same Equidistant treatment with Centre scale; inspect central scale and perimeter stretch.'),(36,'Projection-Full-Frame',{'projectionFraming':0},'Same Equidistant treatment with Full frame; inspect framing loss and filling of the frame.')]:
 add(Path(f'demonstrations/{n}-Demo-{title}.ldbpreset'),None,projection|chg,note)
add(Path('cinematic-lenses/29-Balanced-Wide-Street.ldbpreset'),Path('cinematic-lenses/14-Stressed-Ultra-Wide-2-Medium.ldbpreset'),projection|dict(projectionAmount=20,distortionK1=-.008,distortionK2=.035,moustacheK3=.045,peripheralWarp=.06,peripheralStretch=.08,cornerSharpnessLoss=.38,radialSmear=.16),'Restrained equidistant wide character; reduce stacked moustache/peripheral warp so projection carries the geometry. Compare with existing Stressed Ultra Wide Medium.')
add(Path('cinematic-lenses/30-Gentle-Stereo-Documentary.ldbpreset'),Path('cinematic-lenses/04-Breathing-Documentary-Zoom-2-Medium.ldbpreset'),projection|dict(projectionModel=2,projectionAmount=20),'Gentle stereographic expansion layered on documentary character; compare with existing Documentary Zoom Medium. Reject if framing cost outweighs the visual benefit.')
for n,title,k,value,note in [(37,'Projection-Amount','projectionAmount',20,'Compare Amount 20% with 45%, holding Equidistant, 55 degrees and Balanced fixed.'),(38,'Projection-Field-Angle','projectionFieldAngle',75,'Compare Field Angle 75 degrees with 55 degrees, holding Equidistant, Amount 45% and Balanced fixed; inspect composition loss.')]:
 add(Path(f'demonstrations/{n}-Demo-{title}.ldbpreset'),Path('demonstrations/33-Demo-Equidistant-Projection.ldbpreset'),{k:value},note)
 rows[-1]['baseline_engine']='1.70'
r=next(r for r in rows if r['label']=='26-Internal-Field-Edge-FX')
p=repo/r['candidate'];p.write_text('\n'.join(line for line in p.read_text().splitlines() if not line.startswith('prismDistribution='))+'\n')
r['changes']['prismDistribution']=0;r['decision']='remove dormant setting';r['rationale']='Preserve the passed compound treatment; remove inactive Prism Distribution rather than introduce a new effect.';r['warnings']=[]
assert len(rows)==115 and sum(r['decision']=='revise ranges' for r in rows[:107])==59
# First batch covers every kind of range issue, one wide creative baseline,
# and the six additions. Remaining revisions stay available for focused batches.
selected=[];covered=set()
for r in rows[:107]:
 keys=set(r['changes'])
 if keys-covered:selected.append(r['id']);covered|=keys
selected += [r['id'] for r in rows[107:]]
manifest=dict(baseline='1.69 / 4bd0dd1',original_count=107,candidate_count=113,range_revision_count=59,rows=rows,batches={'first':selected},notes=['Range revisions are proposals, not visual passes.','960px framing/character comparisons; sharpness decisions require native-resolution follow-up.','Depth demo requires a real depth-input host check. Still-image tests do not establish motion/export behavior.','Original factory library, schema and release files are untouched.'])
(root/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(root/'review-schema.json').write_text(json.dumps(schema,indent=2)+'\n')
print(f'Reviewed 107 definitions; prepared 59 range corrections, one dormant-setting cleanup and 8 additions. First batch: {len(selected)} presets, two sources each.')
