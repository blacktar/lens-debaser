#!/usr/bin/env python3
"""Stage only the isolated candidate and its six examples."""
from pathlib import Path
import plistlib,shutil,subprocess,sys
root=Path(sys.argv[1]);bundle=root/'LensDebaserProjectionTest.ofx.bundle'
resources=bundle/'Contents/Resources';resources.mkdir(parents=True,exist_ok=True)
plist=plistlib.loads(Path('resources/Info.plist').read_bytes())
plist.update(CFBundleExecutable='LensDebaserProjectionTest.ofx',CFBundleIdentifier='com.ldb.LensDebaser.ProjectionTest',CFBundleName='Lens Debaser Projection Test',CFBundleShortVersionString='1.69.1',CFBundleVersion='16901',CFBundleIconFile='com.ldb.LensDebaser.ProjectionTest.png')
old=bundle/'Contents/MacOS/LensDebaser.ofx'
if old.exists():old.unlink()
(bundle/'Contents/Info.plist').write_bytes(plistlib.dumps(plist))
shutil.copyfile(root/'LDBOptics.metallib',resources/'LDBOptics.metallib')
subprocess.run(['sips','-z','256','256','resources/ldb.png','--out',str(resources/'com.ldb.LensDebaser.ProjectionTest.png')],check=True,capture_output=True)
presets=resources/'Projection Examples';presets.mkdir(exist_ok=True)
for source in Path('presets/experiments/projection-resolve-candidate').glob('*.ldbpreset'):
 shutil.copyfile(source,presets/source.name)
print(f'Staged {bundle}; distinct identifier, six isolated examples, no public version change.')
