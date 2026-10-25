#!/usr/bin/env python3
"""Submit/resume notarization for the exact verified installer, then staple and assess."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,sys
R=Path(__file__).resolve().parents[2]
os.environ['DEVELOPER_DIR']='/Applications/Xcode.app/Contents/Developer'
a=argparse.ArgumentParser();a.add_argument('--wait-seconds',type=int,default=60);args=a.parse_args()
assert 1<=args.wait_seconds<=300
record_path=Path(json.loads((R/'build/notarization/latest-installer.json').read_text())['record'])
d=json.loads(record_path.read_text());package=Path(d['package']);out=record_path.parent
sha=lambda:hashlib.sha256(package.read_bytes()).hexdigest()
def save():record_path.write_text(json.dumps(d,indent=2)+'\n')
def invoke(cmd,log):
 result=subprocess.run(cmd,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 (out/log).write_text(result.stdout)
 return result
assert sha()==d.get('package_sha256',d['package_sha256_before_stapling']),'Installer changed after verification'
if not d.get('submission_id'):
 result=invoke(['xcrun','notarytool','submit',str(package),'--keychain-profile','LensDebaser-Notary','--output-format','json'],'notary-submit.json')
 if result.returncode:print(result.stdout);raise SystemExit(result.returncode)
 response=json.loads(result.stdout);d['submission_id']=response['id'];d['notarization_status']='submitted';save()
 print('Submitted to Apple:',d['submission_id'],flush=True)
if d.get('notarization_status')!='Accepted':
 result=invoke(['xcrun','notarytool','wait',d['submission_id'],'--keychain-profile','LensDebaser-Notary','--timeout',str(args.wait_seconds)+'s','--output-format','json'],'notary-wait.json')
 info=invoke(['xcrun','notarytool','info',d['submission_id'],'--keychain-profile','LensDebaser-Notary','--output-format','json'],'notary-info.json')
 if info.returncode:print(info.stdout);raise SystemExit(info.returncode)
 response=json.loads(info.stdout);d['notarization_status']=response['status'];save();print('Apple notarization status:',response['status'],flush=True)
 if response['status']=='In Progress':raise SystemExit(2)
 log=invoke(['xcrun','notarytool','log',d['submission_id'],'--keychain-profile','LensDebaser-Notary','--output-format','json'],'notary-log.json')
 if response['status']!='Accepted':print(log.stdout);raise SystemExit(1)
for command,filename in [
 (['xcrun','stapler','staple','--verbose',str(package)],'staple.txt'),
 (['xcrun','stapler','validate','--verbose',str(package)],'staple-validate.txt'),
 (['pkgutil','--check-signature',str(package)],'package-signature.txt'),
 (['spctl','--assess','--type','install','--verbose=4',str(package)],'gatekeeper-assessment.txt')]:
 result=invoke(command,filename)
 if result.returncode:print(result.stdout);raise SystemExit(result.returncode)
d['package_sha256']=sha();d['stapled']=True;d['gatekeeper_install_assessment']='accepted';save()
package.with_suffix('.pkg.sha256').write_text(d['package_sha256']+'  '+package.name+'\n')
print('NOTARIZED, STAPLED AND VERIFIED:',package,flush=True)
print('Resolve installation/upgrade test remains pending; this script does not install software.')
