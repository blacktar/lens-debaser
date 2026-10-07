#!/usr/bin/env python3
"""Validate integrated host and reuse approved byte-identical GPU program evidence."""
from pathlib import Path
import datetime,hashlib,html,importlib.util,json,plistlib,shutil,subprocess,tempfile
repo=Path(__file__).resolve().parent.parent;state=repo/'build/integration/1.70'
subprocess.run(['make','version-check','ofx','build/ldb-control-layout-tests','build/ldb-projection-integration-tests'],cwd=repo,check=True)
installed=Path('/Library/OFX/Plugins/LensDebaser.ofx.bundle')
if (installed/'Contents/Info.plist').is_file():
 current_info=plistlib.loads((repo/'build/LensDebaser.ofx.bundle/Contents/Info.plist').read_bytes())
 installed_info=plistlib.loads((installed/'Contents/Info.plist').read_bytes())
 current_build=int(current_info['CFBundleVersion']);installed_build=int(installed_info['CFBundleVersion'])
 assert current_build>=installed_build,'Build number is older than the installed product.'
 if current_build==installed_build:
  for relative in ['Contents/MacOS/LensDebaser.ofx','Contents/Resources/LDBOptics.metallib']:
   assert (repo/'build/LensDebaser.ofx.bundle'/relative).read_bytes()==(installed/relative).read_bytes(),'Changed code reuses installed build number; increment before validation.'
checks=[]
for cmd in [['/usr/bin/python3','scripts/check-control-layout.py'],['build/ldb-control-layout-tests'],['build/ldb-projection-integration-tests','--host-only']]:checks.append(subprocess.check_output(cmd,cwd=repo,text=True).strip())
candidate=Path((state/'latest-frame-relative-candidate-path.txt').read_text().strip());benchmark=Path((state/'latest-frame-relative-benchmark-path.txt').read_text().strip())
audit=json.loads((benchmark/'validation.json').read_text());assert audit['fixed_exact'] and audit['nonfinite']==0
assert (repo/'build/LDBOptics.metallib').read_bytes()==(benchmark/'candidate.metallib').read_bytes()==(candidate/'LDBOptics.metallib').read_bytes(),'Integrated shader differs from approved candidate; GPU evidence cannot be reused.'
assert (state/'effect-size-candidate-acceptance.json').is_file(),'Candidate approval record missing'
pointer=state/'latest-validation-path.txt'
if pointer.exists():
 previous=Path(pointer.read_text().strip())
 if (previous/'effect-size-evidence.json').is_file():
  current_fp=subprocess.check_output(['/usr/bin/python3','scripts/projection-candidate-fingerprint.py',str(repo/'build/LensDebaser.ofx.bundle')],cwd=repo,text=True).strip()
  if current_fp==(previous/'validated-bundle.sha256').read_text().strip():
   subprocess.run(['/usr/bin/python3','scripts/pass-1.70-integration.py','--inputs-match',str(previous)],cwd=repo,check=True)
   subprocess.run(['open',str(previous/'index.html')],check=False)
   print('Reusing exact completed integrated validation:',previous)
   raise SystemExit(0)
report=repo/'outputs/engine-validation/passes'/('pass-104-integration-1.70-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'));report.mkdir(parents=True)
subprocess.run(['/usr/bin/python3','scripts/audit-integration-factory-presets.py',str(report/'factory-audit.json')],cwd=repo,check=True)
assert not json.loads((report/'factory-audit.json').read_text())['blocking_errors']
# Sign in staging outside Documents, then preserve the same signed distribution in both places.
staging=Path(tempfile.mkdtemp(prefix='ldb-integrated-',dir='/private/tmp'))/'LensDebaser.ofx.bundle'
subprocess.run(['ditto','--norsrc','--noextattr',str(repo/'build/LensDebaser.ofx.bundle'),str(staging)],check=True)
subprocess.run(['xattr','-cr',str(staging)],check=True);subprocess.run(['codesign','--force','--deep','--sign','-',str(staging)],check=True);subprocess.run(['codesign','--verify','--deep','--strict',str(staging)],check=True)
for destination in [repo/'build/LensDebaser.ofx.bundle',report/'LensDebaser.ofx.bundle']:
 subprocess.run(['ditto','--norsrc','--noextattr',str(staging),str(destination)],check=True)
 subprocess.run(['xattr','-cr',str(destination)],check=True)
 subprocess.run(['codesign','--verify','--deep','--strict',str(destination)],check=True)
factory=report/'FactoryPresets';factory.mkdir()
for directory in ['demonstrations','cinematic-lenses']:shutil.copytree(repo/'presets'/directory,factory/directory)
shutil.copy2(repo/'presets/README.md',factory/'README.md')
shutil.copytree(benchmark/'images',report/'images')
# Existing swipe HTML and timing table; all data stays human-readable in this report.
doc=(benchmark/'index.html').read_text();a=doc.index('<header>');b=doc.index('</header>',a)+len('</header>')
doc=doc[:a]+'''<header><h1>Integrated Lens Debaser 1.70 · Effect Size</h1><p>Normal plugin identity; Frame Relative default, Fixed Pixels alternative. Short tooltip and preset load/save integrated. The shader is byte-identical to the visually approved candidate, so its completed render/benchmark evidence below is reused without rerendering.</p><p>Host/control checks: '''+html.escape(' · '.join(checks))+'''</p><p>Fixed Pixels matched the installed previous engine exactly. All tested components finite. Existing factory recipes are preserved for the next review phase. User approved the candidate for integration; the integrated host checks passed. Normal Resolve verification remains a post-install step.</p><p>Frame Relative also becomes the default for old presets or instances lacking the new setting; choose Fixed Pixels to retain legacy sizing. No automatic old-project migration is claimed.</p></header>'''+doc[b:]
factory_audit=json.loads((report/'factory-audit.json').read_text())
issues=''.join('<tr><td>'+html.escape(row['preset'])+'</td><td>'+html.escape('; '.join(row['issues']))+'</td></tr>' for row in factory_audit['presets'] if row['issues'])
doc=doc.replace('</main>','<article><h2>Existing factory review</h2><p>'+str(factory_audit['preset_count'])+' unchanged recipes preserved; '+str(factory_audit['legacy_issue_presets'])+' legacy range flags, zero integration blockers. These remain factory-review work, not approved new presets.</p><table><tr><th>Preset</th><th>Review flag</th></tr>'+issues+'</table></article></main>')
(report/'index.html').write_text(doc)
subprocess.run(['/usr/bin/python3','scripts/build-control-layout-review.py',str(report/'control-layout-review.html'),'1.70'],cwd=repo,check=True)
spec=importlib.util.spec_from_file_location('schema_builder',repo/'scripts/build-preset-schema.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);module.OUTPUT=report/'Lens-Debaser-Preset-Schema-1.70-draft.json';module.main()
fp=subprocess.check_output(['/usr/bin/python3','scripts/projection-candidate-fingerprint.py',str(report/'LensDebaser.ofx.bundle')],cwd=repo,text=True).strip();(report/'validated-bundle.sha256').write_text(fp+'\n')
(report/'effect-size-evidence.json').write_text(json.dumps(dict(candidate=str(candidate),benchmark=str(benchmark),shader_sha256=hashlib.sha256((repo/'build/LDBOptics.metallib').read_bytes()).hexdigest(),checks=checks,gpu_evidence_reused=True,normal_resolve_check_pending=True),indent=2)+'\n')
(state/'latest-validation-path.txt').write_text(str(report)+'\n')
chat=Path('/Users/blacktar/Documents/Codex/2026-10-04/continue-the-lens-debaser-project-from/outputs');visible=doc.replace('src="images/','src="'+(report/'images').as_uri()+'/');published=chat/'Lens-Debaser-1.70-Effect-Size-Integration.html';published.write_text(visible)
subprocess.run(['open',str(published)],check=False)
print('Integrated validation ready:',published,'\nNo acceptance or installation performed.')
