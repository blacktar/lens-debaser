#!/usr/bin/env python3
"""Verify exact released host-source scope and final notarized installer payload."""
from pathlib import Path
import json,hashlib,subprocess,tempfile,plistlib,ctypes,tarfile
R=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
a=json.loads((R/'docs/release-1.73-acceptance.json').read_text());src=R/'scripts/release-1.73/LensDebaserPlugin.cpp';assert sha(src)==a['release_host_source_sha256']
record=Path(json.loads((R/'build/notarization/latest-installer.json').read_text())['record']);d=json.loads(record.read_text());assert d['version']=='1.73' and d['stapled'] and d['notarization_status']=='Accepted';pkg=Path(d['package']);assert sha(pkg)==d['package_sha256']
with tempfile.TemporaryDirectory(dir='/private/tmp',prefix='ldb173-final-') as t:
 root=Path(t)/'expanded';subprocess.run(['pkgutil','--expand-full',str(pkg),str(root)],check=True)
 bundle=next(root.glob('**/Payload/Library/OFX/Plugins/LensDebaser.ofx.bundle'));info=plistlib.loads((bundle/'Contents/Info.plist').read_bytes());assert info['CFBundleName']=='Lens Debaser 1.73' and info['CFBundleVersion']=='173'
 exe=bundle/'Contents/MacOS/LensDebaser.ofx';assert sha(exe)==d['bundle_executable_sha256'];assert sha(bundle/'Contents/Resources/LDBOptics.metallib')==a['optics_sha256'];assert exe.stat().st_mode&0o111
 subprocess.run(['codesign','--verify','--deep','--strict',str(bundle)],check=True)
 class Plugin(ctypes.Structure):
  _fields_=[('api',ctypes.c_char_p),('apiVersion',ctypes.c_int),('identifier',ctypes.c_char_p),('major',ctypes.c_uint),('minor',ctypes.c_uint),('setHost',ctypes.c_void_p),('entry',ctypes.c_void_p)]
 lib=ctypes.CDLL(str(exe));lib.OfxGetPlugin.restype=ctypes.POINTER(Plugin);p=lib.OfxGetPlugin(0).contents;assert p.identifier==b'com.ldb.LensDebaser' and (p.major,p.minor)==(1,73)
 shared=bundle.parents[2]/'Application Support/Lens Debaser';assert len(list((shared/'Factory Presets').rglob('*.ldbpreset')))==133
 assert '1.73' in (shared/'Preset Authoring Kit/Lens-Debaser-Preset-Schema.json').read_text()
 with tarfile.open(R/'releases/Lens-Debaser-1.73-Source.tar.gz') as z:
  assert z.extractfile('Lens-Debaser-1.73-Source/src/ofx/LensDebaserPlugin.cpp').read()==src.read_bytes()
  assert hashlib.sha256(z.extractfile('Lens-Debaser-1.73-Source/build/LDBOptics.metallib').read()).hexdigest()==a['optics_sha256']
print('PASS: final package, stable 1.73 label and ID, host API version, exact optics, 133 presets, kit and release-source archive.')
