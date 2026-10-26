#!/usr/bin/env python3
from pathlib import Path
import ctypes,hashlib,json,plistlib,subprocess,tempfile,zipfile
E=Path(__file__).resolve().parent;out=E/'out';package=out/'LensDebaserPresetCopyTest.zip';proof=json.loads((out/'build.json').read_text())
assert hashlib.sha256(package.read_bytes()).hexdigest()==proof['zip_sha256']
with tempfile.TemporaryDirectory(prefix='ldb-copy-verify-',dir='/private/tmp') as temp:
 subprocess.run(['ditto','-x','-k','--norsrc','--noextattr',str(package),temp],check=True)
 bundle=Path(temp)/'LensDebaserPresetCopyTest.ofx.bundle';exe=bundle/'Contents/MacOS'/bundle.name.removesuffix('.bundle')
 info=plistlib.loads((bundle/'Contents/Info.plist').read_bytes())
 assert info['CFBundleExecutable']==exe.name and info['CFBundleIdentifier']=='com.ldb.LensDebaser.PresetCopyTest'
 assert exe.stat().st_mode&0o111
 assert hashlib.sha256(exe.read_bytes()).hexdigest()==proof['plugin_sha256']
 assert hashlib.sha256((bundle/'Contents/Resources/LDBOptics.metallib').read_bytes()).hexdigest()==proof['optics_sha256']
 subprocess.run(['codesign','--verify','--deep','--strict',str(bundle)],check=True)
 assert 'arm64' in subprocess.check_output(['file',str(exe)],text=True)
 library=ctypes.CDLL(str(exe));assert library.OfxGetNumberOfPlugins()==1
 class Plugin(ctypes.Structure):
  _fields_=[('api',ctypes.c_char_p),('apiVersion',ctypes.c_int),('identifier',ctypes.c_char_p),('major',ctypes.c_uint),('minor',ctypes.c_uint),('setHost',ctypes.c_void_p),('entry',ctypes.c_void_p)]
 library.OfxGetPlugin.restype=ctypes.POINTER(Plugin)
 assert library.OfxGetPlugin(0).contents.identifier==b'com.ldb.LensDebaser.PresetCopyTest'
print('PASS: extracted package layout, executable, identity, permissions, arm64, signature, hashes and dynamic loading.')
