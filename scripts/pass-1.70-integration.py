#!/usr/bin/env python3
"""Record explicit human acceptance; bind deploy to the reviewed bundle/presets."""
from pathlib import Path
import datetime,json,shutil,subprocess,sys
repo=Path(__file__).resolve().parent.parent
state=repo/'build/integration/1.70'
def fingerprint(path):
 return subprocess.check_output(['/usr/bin/python3',str(repo/'scripts/projection-candidate-fingerprint.py'),str(path)],text=True).strip()
def inputs_match(report):
 current=repo/'presets'; snapshot=report/'FactoryPresets'
 if snapshot.is_dir():
  for d in ['demonstrations','cinematic-lenses']:
   a={p.name:p.read_bytes() for p in (current/d).glob('*.ldbpreset')}
   b={p.name:p.read_bytes() for p in (snapshot/d).glob('*.ldbpreset')}
   assert a==b,'Factory inputs changed after validation'
  assert (current/'README.md').read_bytes()==(snapshot/'README.md').read_bytes()
 else:
  audit=json.loads((report/'factory-audit.json').read_text())
  names={row['preset'] for row in audit['presets']}
  present={str(p.relative_to(repo)) for d in ['demonstrations','cinematic-lenses'] for p in (current/d).glob('*.ldbpreset')}
  assert names==present
  for row in audit['presets']:
   assert row['unchanged_release'],'Older report lacks a verifiable factory snapshot'
   assert subprocess.check_output(['git','show','4bd0dd1:'+row['preset']],cwd=repo)==(repo/row['preset']).read_bytes(),'Factory input changed after validation'
  assert subprocess.check_output(['git','show','4bd0dd1:presets/README.md'],cwd=repo)==(current/'README.md').read_bytes(),'Factory documentation changed after validation'
def approved():
 record=json.loads((state/'passed-build.json').read_text())
 report=Path(record['report']);factory=Path(record['factory_snapshot']);bundle=report/'LensDebaser.ofx.bundle'
 assert str(report).startswith(str(repo/'outputs/engine-validation/passes/pass-104-integration-1.70-'))
 assert fingerprint(bundle)==record['bundle_fingerprint']==(report/'validated-bundle.sha256').read_text().strip(),'Passed bundle changed'
 assert fingerprint(factory)==record['factory_fingerprint'],'Passed factory snapshot changed'
 assert fingerprint(repo/'build/LensDebaser.ofx.bundle')==record['bundle_fingerprint'],'Current build differs from passed build; validate and review it first'
 # Only distribution files participate; images, archives and unrelated test folders do not.
 current=repo/'presets'
 for relative in ['demonstrations','cinematic-lenses']:
  a={str(p.relative_to(current)):p.read_bytes() for p in (current/relative).glob('*.ldbpreset')}
  b={str(p.relative_to(factory)):p.read_bytes() for p in (factory/relative).glob('*.ldbpreset')}
  assert a==b,'Factory presets differ from passed inputs; validate and review them first'
 assert (current/'README.md').read_bytes()==(factory/'README.md').read_bytes(),'Factory documentation differs from passed inputs'
 return bundle,factory
if __name__=='__main__':
 try:
  if len(sys.argv)==3 and sys.argv[1]=='--inputs-match':
   inputs_match(Path(sys.argv[2]))
  elif sys.argv[1:]==['--check']:
   bundle,factory=approved();print(bundle);print(factory)
  elif sys.argv[1:]==['--accept']:
   report=Path((state/'latest-validation-path.txt').read_text().strip())
   assert str(report).startswith(str(repo/'outputs/engine-validation/passes/pass-104-integration-1.70-'))
   bundle=report/'LensDebaser.ofx.bundle';fp=fingerprint(bundle)
   assert fp==(report/'validated-bundle.sha256').read_text().strip()
   assert fingerprint(repo/'build/LensDebaser.ofx.bundle')==fp,'Current build changed after validation'
   audit=json.loads((report/'factory-audit.json').read_text());assert not audit['blocking_errors']
   inputs_match(report)
   stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
   factory=state/'passed-inputs'/stamp/'FactoryPresets'
   if (report/'FactoryPresets').is_dir():
    shutil.copytree(report/'FactoryPresets',factory)
   else:
    # Migration for the existing pass: reconstruct only exact released 1.69
    # preset inputs proven by its audit. Never silently accept later edits.
    names={row['preset'] for row in audit['presets']}
    current={str(p.relative_to(repo)) for d in ['demonstrations','cinematic-lenses'] for p in (repo/'presets'/d).glob('*.ldbpreset')}
    assert names==current
    for row in audit['presets']:
     assert row['unchanged_release'],'Older report lacks a verifiable factory snapshot'
     old=subprocess.check_output(['git','show','4bd0dd1:'+row['preset']],cwd=repo)
     assert old==(repo/row['preset']).read_bytes(),'Factory input changed after validation'
    for d in ['demonstrations','cinematic-lenses']:shutil.copytree(repo/'presets'/d,factory/d)
    shutil.copy2(repo/'presets/README.md',factory/'README.md')
   record=dict(accepted_at=stamp,acceptance='Explicit user acceptance of integration benchmarks and visual comparisons; factory 1.70 re-evaluation remains separate',report=str(report),bundle_fingerprint=fp,factory_snapshot=str(factory),factory_fingerprint=fingerprint(factory))
   (state/'passed-build.json').write_text(json.dumps(record,indent=2)+'\n')
   approved()
   print('Integration marked passed. make deploy may install this exact reviewed snapshot.')
  else:raise AssertionError('Use --accept only after explicit review/sign-off, or --check to verify deploy eligibility')
 except (AssertionError,OSError,KeyError,ValueError) as e:
  print('Not deployable:',e,file=sys.stderr);print('Complete separate validation and explicit integration sign-off first.',file=sys.stderr);raise SystemExit(1)
