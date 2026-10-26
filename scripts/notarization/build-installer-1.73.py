#!/usr/bin/env python3
"""Build a Developer ID installer from approved 1.73 evidence, without rebuilding optics."""
from pathlib import Path
from datetime import datetime
from zoneinfo import ZoneInfo
import ctypes,hashlib,json,os,plistlib,shutil,subprocess,tempfile,zipfile,re,xml.etree.ElementTree as ET
R=Path(__file__).resolve().parents[2]
APP='Developer ID Application: Vidar Andersen (CMRVMTA2G5)'
INSTALLER='Developer ID Installer: Vidar Andersen (CMRVMTA2G5)'
TEAM='CMRVMTA2G5'
def run(args,**kw):return subprocess.run(list(map(str,args)),check=True,**kw)
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
release=json.loads((R/'build/release-1.73/build.json').read_text())
passed=Path(release['bundle'])
assert release['resolve_feature_pass']
assert digest(passed/'Contents/MacOS/LensDebaser.ofx')==release['executable_sha256']
acceptance=release
archive=R/'releases/Lens-Debaser-1.72-Apple-Silicon.zip'
expected=(archive.with_suffix('.zip.sha256')).read_text().split()[0]
assert digest(archive)==expected,'Original release archive checksum mismatch'
date=datetime.now(ZoneInfo('Europe/Berlin')).strftime('%Y%m%d');revision=1
out=R/'releases/installer-candidates/1.73';out.mkdir(parents=True,exist_ok=True)
while (out/f'{date}_v{revision}').exists():revision+=1
out=out/f'{date}_v{revision}';out.mkdir()
name=f'Lens-Debaser-1.73-Apple-Silicon-{date}_v{revision}'
with tempfile.TemporaryDirectory(prefix='ldb-signed-installer-',dir='/private/tmp') as folder:
 work=Path(folder);root=work/'payload';bundle=root/'Library/OFX/Plugins/LensDebaser.ofx.bundle'
 shared=root/'Library/Application Support/Lens Debaser';shared.mkdir(parents=True)
 bundle.parent.mkdir(parents=True)
 run(['ditto','--norsrc','--noextattr',passed,bundle])
 # Only approved distributed data is extracted; old shell installer and ad-hoc signing are excluded.
 with zipfile.ZipFile(archive) as z:
  for item in z.infolist():
   parts=Path(item.filename).parts[1:]
   if not parts or item.is_dir():continue
   if parts[0]=='Presets':relative=Path('Factory Presets',*parts[1:])
   elif parts[0]=='Preset Authoring Kit':relative=Path(*parts)
   elif parts[0]=='THIRD-PARTY-NOTICES.txt':relative=Path(parts[0])
   else:continue
   assert '..' not in relative.parts
   target=shared/relative;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(z.read(item))
 for p in (shared/'Preset Authoring Kit').rglob('*'):
  if p.is_file() and p.suffix.lower() in {'.json','.md','.txt'}:
   p.write_text(p.read_text().replace('1.72','1.73').replace('v1.72','v1.73'))
 approved=json.loads((R/'presets/approved-1.72.json').read_text())['files']
 recipes=list((shared/'Factory Presets').rglob('*.ldbpreset'));assert len(recipes)==len(approved)==133
 for path in recipes:
  matches=[text for key,text in approved.items() if Path(key).name==path.name]
  assert len(matches)==1 and path.read_text()==matches[0],path.name
 readme='''Lens Debaser 1.73 — Apple Silicon

Quit DaVinci Resolve before installation. This installer installs Lens Debaser
for all users of this Mac. Restart Resolve after installation.

Plug-in: /Library/OFX/Plugins/LensDebaser.ofx.bundle
Factory presets: /Library/Application Support/Lens Debaser/Factory Presets
Preset Authoring Kit: /Library/Application Support/Lens Debaser/Preset Authoring Kit

In Lens Debaser, use Load to open a preset from the Factory Presets folder.
Existing presets in your personal Library are left in place. Files you create
should be saved outside the system-managed Factory Presets folder.

An existing installed plug-in is copied to a dated directory under
/Library/Application Support/Lens Debaser/Backups before replacement.

User guide: https://vidarandersen.com/dmz/lens-debaser-ofx/
Issues: https://github.com/blacktar/lens-debaser/issues

'''
 (shared/'README.txt').write_text(readme)
 (shared/'LICENSE.txt').write_bytes((R/'LICENSE').read_bytes())
 for p in root.rglob('*'):os.chmod(p,0o755 if p.is_dir() else 0o644)
 exe=bundle/'Contents/MacOS/LensDebaser.ofx';os.chmod(exe,0o755)
 macho=[]
 for p in root.rglob('*'):
  if p.is_file():
   with p.open('rb') as f:magic=f.read(4)
   if magic in (b'\xcf\xfa\xed\xfe',b'\xfe\xed\xfa\xcf',b'\xca\xfe\xba\xbe'):macho.append(p)
 assert macho==[exe],f'Unexpected native executable inventory: {macho}'
 assert digest(bundle/'Contents/Resources/LDBOptics.metallib')==acceptance['shader_sha256']
 # Sign the one code bundle explicitly; do not use --deep to sign nested code.
 run(['xattr','-cr',bundle])
 run(['codesign','--force','--options','runtime','--timestamp','--sign',APP,bundle])
 run(['codesign','--verify','--deep','--strict','--verbose=2',bundle])
 signature=subprocess.check_output(['codesign','-d','--verbose=4',bundle],stderr=subprocess.STDOUT,text=True)
 assert 'TeamIdentifier='+TEAM in signature and 'runtime' in signature and 'Timestamp=' in signature
 minimum=int(re.search(r'VersionMin=(\d+)',signature).group(1))
 minimum_os=f'{minimum>>16}.{(minimum>>8)&255}.{minimum&255}'
 readme=readme.replace('Lens Debaser 1.73 — Apple Silicon','Lens Debaser 1.73 — Apple Silicon\nRequires macOS '+minimum_os+' or later.')
 (shared/'README.txt').write_text(readme)
 library=ctypes.CDLL(str(exe));assert library.OfxGetNumberOfPlugins()==1
 class Plugin(ctypes.Structure):
  _fields_=[('api',ctypes.c_char_p),('apiVersion',ctypes.c_int),('identifier',ctypes.c_char_p),('major',ctypes.c_uint),('minor',ctypes.c_uint),('setHost',ctypes.c_void_p),('entry',ctypes.c_void_p)]
 library.OfxGetPlugin.restype=ctypes.POINTER(Plugin)
 assert library.OfxGetPlugin(0).contents.identifier==b'com.ldb.LensDebaser'
 scripts=work/'scripts';scripts.mkdir()
 preinstall='''#!/bin/bash
set -euo pipefail
if /usr/bin/pgrep -x Resolve >/dev/null; then
  echo "Quit DaVinci Resolve before installing Lens Debaser." >&2
  exit 1
fi
volume="${3:-/}"
installed="$volume/Library/OFX/Plugins/LensDebaser.ofx.bundle"
if [[ -d "$installed" ]]; then
  backup="$volume/Library/Application Support/Lens Debaser/Backups/Before-PKG-$(date +%Y%m%d-%H%M%S)"
  /bin/mkdir -p "$backup"
  /usr/bin/ditto --norsrc --noextattr "$installed" "$backup/LensDebaser.ofx.bundle"
fi
exit 0
'''
 (scripts/'preinstall').write_text(preinstall);os.chmod(scripts/'preinstall',0o755)
 run(['/bin/bash','-n',scripts/'preinstall'])
 components=work/'components.plist'
 run(['pkgbuild','--analyze','--root',root,components])
 config=plistlib.loads(components.read_bytes())
 for entry in config:
  entry['BundleIsRelocatable']=False
  entry['BundleIsVersionChecked']=False
 components.write_bytes(plistlib.dumps(config))
 component=work/'LensDebaserPayload.pkg'
 run(['pkgbuild','--root',root,'--install-location','/','--identifier','com.ldb.LensDebaser.pkg','--version','1.73','--ownership','recommended','--component-plist',components,'--scripts',scripts,'--sign',INSTALLER,component])
 ui=work/'ui';ui.mkdir();(ui/'Welcome.txt').write_text('Lens Debaser 1.73 for Apple Silicon\n\nQuit Resolve before continuing. The installer installs the plug-in, factory presets and AI Preset Authoring Kit.\n\nAn existing plug-in is backed up. Your personal presets are retained.\n')
 (ui/'ReadMe.txt').write_text(readme)
 distribution=work/'Distribution.xml'
 requirements=work/'requirements.plist';requirements.write_bytes(plistlib.dumps({'arch':['arm64'],'os':[minimum_os]}))
 run(['productbuild','--synthesize','--product',requirements,'--package',component,distribution])
 xml=ET.parse(distribution);doc=xml.getroot()
 title=ET.Element('title');title.text='Lens Debaser 1.73';doc.insert(0,title)
 ET.SubElement(doc,'welcome',{'file':'Welcome.txt'});ET.SubElement(doc,'readme',{'file':'ReadMe.txt'})
 domains=doc.find('domains')
 if domains is None:domains=ET.SubElement(doc,'domains')
 domains.attrib.update(enable_localSystem='true',enable_currentUserHome='false',enable_anywhere='false')
 for ref in doc.findall('pkg-ref'):
  if ref.text and component.name in ref.text:ref.text=component.name
 xml.write(distribution,encoding='utf-8',xml_declaration=True)
 package=out/(name+'.pkg')
 run(['productbuild','--distribution',distribution,'--package-path',work,'--resources',ui,'--sign',INSTALLER,package])
 run(['pkgutil','--check-signature',package])
 expanded=work/'expanded';run(['pkgutil','--expand-full',package,expanded])
 extracted=next(expanded.glob('**/Payload/Library/OFX/Plugins/LensDebaser.ofx.bundle'))
 run(['codesign','--verify','--deep','--strict',extracted])
 assert digest(extracted/'Contents/MacOS/LensDebaser.ofx')==digest(exe)
 assert digest(extracted/'Contents/Resources/LDBOptics.metallib')==acceptance['shader_sha256']
 for p in (shared/'Factory Presets').rglob('*'):
  if p.is_file():assert digest(p)==digest(extracted.parents[2]/'Application Support/Lens Debaser/Factory Presets'/p.relative_to(shared/'Factory Presets'))
 extracted_pre=next(expanded.glob('**/Scripts/preinstall'))
 assert extracted_pre.read_text()==preinstall
 record={'version':'1.73','build':173,'minimum_macos':minimum_os,'package':str(package),'package_sha256_before_stapling':digest(package),'bundle_executable_sha256':digest(exe),'optics_sha256':acceptance['shader_sha256'],'original_release_zip_sha256':expected,'team':TEAM,'preset_count':133,'native_code_inventory':['LensDebaser.ofx.bundle/Contents/MacOS/LensDebaser.ofx'],'notarization_status':'not submitted','resolve_install_test':'pending','signature':signature}
 (out/'build.json').write_text(json.dumps(record,indent=2)+'\n')
 (out/'Installer-README.txt').write_text(readme)
 (R/'build/notarization').mkdir(parents=True,exist_ok=True)
 (R/'build/notarization/latest-installer.json').write_text(json.dumps({'record':str(out/'build.json')},indent=2)+'\n')
 print('VERIFIED SIGNED INSTALLER:',package,flush=True)
