#!/usr/bin/env python3
"""Prepare stable 1.73 from the user-passed preset-copy snapshot and exact 1.72 optics."""
from pathlib import Path
import json,hashlib,shutil,subprocess,plistlib,tarfile,os
R=Path(__file__).resolve().parents[2];E=R/'experiments/preset-copy';S=R/'build/release-1.73/source'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
proof=json.loads((R/'docs/release-1.73-acceptance.json').read_text());assert proof['resolve_feature_pass']
# Reconstruct only the released source base, then apply the exact tested host-side source.
S.mkdir(parents=True,exist_ok=True)
paths=subprocess.check_output(['git','ls-tree','-r','--name-only','30902a7','Makefile','include','src','resources'],cwd=R,text=True).splitlines()
for path in paths:
 p=S/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(subprocess.check_output(['git','show','30902a7:'+path],cwd=R))
source=Path(__file__).parent/'LensDebaserPlugin.cpp'
assert sha(source)==proof['release_host_source_sha256']
s=source.read_text()
(S/'src/ofx/LensDebaserPlugin.cpp').write_text(s)
shutil.copyfile(E/'PresetState.h',S/'include/LDBPresetState.h')
mk=(S/'Makefile').read_text();a=mk.index('$(METAL_AIR):');b=mk.index('$(FIELD_PSF_AIR):',a);mk=mk[:a]+'$(METAL_LIB):\n\t@test -f \"$@\"\n\n'+mk[b:];mk+='\n$(OFX_BUILD)/LensDebaserPlugin.o: include/LDBPresetState.h\n';(S/'Makefile').write_text(mk)
info=plistlib.loads((S/'resources/Info.plist').read_bytes());info.update(CFBundleName='Lens Debaser 1.73',CFBundleShortVersionString='1.73',CFBundleVersion='173',CFBundleIdentifier='com.ldb.LensDebaser');info.pop('LDBReleaseCandidate',None);(S/'resources/Info.plist').write_bytes(plistlib.dumps(info))
import zipfile
archive=R/'releases/Lens-Debaser-1.72-Apple-Silicon.zip'
assert sha(archive)==(archive.with_suffix('.zip.sha256')).read_text().split()[0]
with zipfile.ZipFile(archive) as z:
 metal=z.read(next(n for n in z.namelist() if n.endswith('/Contents/Resources/LDBOptics.metallib')))
assert hashlib.sha256(metal).hexdigest()==proof['optics_sha256'];(S/'build').mkdir(exist_ok=True);(S/'build/LDBOptics.metallib').write_bytes(metal)
os.environ['MACOSX_DEPLOYMENT_TARGET']='26.0'
subprocess.run(['make','ofx'],cwd=S,check=True)
b=S/'build/LensDebaser.ofx.bundle';assert sha(b/'Contents/Resources/LDBOptics.metallib')==proof['optics_sha256']
record={'version':'1.73','build':173,'bundle':str(b),'executable_sha256':sha(b/'Contents/MacOS/LensDebaser.ofx'),'shader_sha256':proof['optics_sha256'],'tested_candidate_zip_sha256':proof['zip_sha256'],'tested_host_source_sha256':proof.get('tested_host_source_sha256',proof['plugin_sha256']),'release_host_source_sha256':sha(S/'src/ofx/LensDebaserPlugin.cpp'),'resolve_feature_pass':True,'stable_installer_resolve_test':'pending','scope':'Full preset catalogue persistence; identity/version promotion only; exact approved 1.72 optics.'}
(R/'build/release-1.73/build.json').write_text(json.dumps(record,indent=2)+'\n')
# Source archive is self-contained and excludes all generated binaries.
archive=R/'releases/Lens-Debaser-1.73-Source.tar.gz'
with tarfile.open(archive,'w:gz') as out:
 for path in paths:
  out.add(S/path,arcname='Lens-Debaser-1.73-Source/'+path,recursive=False)
 out.add(S/'include/LDBPresetState.h',arcname='Lens-Debaser-1.73-Source/include/LDBPresetState.h')
 out.add(S/'build/LDBOptics.metallib',arcname='Lens-Debaser-1.73-Source/build/LDBOptics.metallib')
 for rel in ['LICENSE','resources/THIRD-PARTY-NOTICES.txt']:
  if rel not in paths:out.add(R/rel,arcname='Lens-Debaser-1.73-Source/'+rel)
print('Prepared stable release:',b,flush=True)
