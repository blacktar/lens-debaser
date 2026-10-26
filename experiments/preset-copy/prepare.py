#!/usr/bin/env python3
from pathlib import Path
import subprocess,tarfile,io,json,hashlib,plistlib,shutil,tempfile,sys
E=Path(__file__).resolve().parent;R=E.parents[1];S=E/'snapshot'
REV='30902a7'
def original(p):return subprocess.check_output(['git','show',REV+':'+p],cwd=R,text=True)
def write(p,s):
 if not p.exists() or p.read_text()!=s:p.write_text(s)
if not (S/'Makefile').exists():
 S.mkdir(parents=True,exist_ok=True)
 paths=subprocess.check_output(['git','ls-tree','-r','--name-only',REV,'Makefile','include','src','resources'],cwd=R,text=True).splitlines()
 for path in paths:
  target=S/path;target.parent.mkdir(parents=True,exist_ok=True)
  data=subprocess.check_output(['git','show',REV+':'+path],cwd=R)
  target.write_bytes(data)
write(S/'include/LDBPresetState.h',(E/'PresetState.h').read_text())
s=original('src/ofx/LensDebaserPlugin.cpp')
s=s.replace('#include <fstream>','#include <fstream>\n#include <iomanip>')
s=s.replace('class Processor final', '#include "LDBPresetState.h"\n\nclass Processor final',1)
s=s.replace('constexpr const char *kName = "Lens Debaser 1.72 RC1";','constexpr const char *kName = "Lens Debaser Preset Copy Test";')
s=s.replace('constexpr const char *kIdentifier = "com.ldb.LensDebaser";','constexpr const char *kIdentifier = "com.ldb.LensDebaser.PresetCopyTest";')
s=s.replace('    presetChoice = fetchChoiceParam("preset");','    presetChoice = fetchChoiceParam("preset");\n    presetReference = fetchStringParam("presetReferenceState");',1)
# Constructor restoration is UI-only: all parameter handles have been fetched.
needle='    updateV4Controls();\n  }\n  void render'
assert needle in s
s=s.replace(needle,'    updateV4Controls();\n    reconcilePresetState(0);\n  }\n  void render',1)
s=s.replace('    if (inPresetChange)\n      return;','    if (inPresetChange)\n      return;\n    lastPresetStateTime=args.time;\n    if(name=="presetReferenceState"){reconcilePresetState(args.time);return;}',1)
s=s.replace('    if (name == "loadPreset") {','    if (name == "loadPreset" && args.reason==OFX::eChangeUserEdit) {',1)
s=s.replace('    if (name == "savePreset") {','    if (name == "savePreset" && args.reason==OFX::eChangeUserEdit) {',1)
s=s.replace('    if (name == "preset") {','    if (name == "preset") {\n      if(args.reason!=OFX::eChangeUserEdit){reconcilePresetState(args.time);return;}',1)
s=s.replace('        comparisonPresetIndex = -1;','        persistPresetReference(nullptr,true);\n        comparisonPresetIndex = -1;',1)
start=s.index('    if (isPresetControl(name)) {');end=s.index('\n  }\n\nprivate:',start)
s=s[:start]+'''    if (isPresetControl(name))reconcilePresetState(args.time);
'''+s[end:]
s=s.replace('\nprivate:\n  double value', '''
  void endChanged(OFX::InstanceChangeReason) override {
    if(!inPresetChange)reconcilePresetState(lastPresetStateTime);
  }
private:
  void persistPresetReference(const Preset* p,bool custom=false) {
    const std::string payload=!loaded.empty()?encodePresetLibrary(loaded,p?comparisonPresetIndex-2:(custom?-1:-2)):(p?encodePresetState(*p):(custom?"CUSTOM":""));
    cachedPresetReference=payload;
    presetReference->setValue(payload);
  }
  void reconcilePresetState(double time) {
    if(inPresetChange)return;
    inPresetChange=true;
    std::string payload;presetReference->getValue(payload);
    if(payload!=cachedPresetReference) {
      loaded.clear();comparisonPresetIndex=-1;editedPresetIndex=-1;
      Preset reference;std::vector<Preset> catalog;int active=0;
      bool restored=decodePresetLibrary(payload,catalog,active);
      if(!restored&&decodePresetState(payload,reference)){catalog.push_back(std::move(reference));restored=true;}
      if(restored) {
        bool complete=true;
        for(const auto& item:catalog) {
          complete=complete&&item.values.size()==std::size(kSpecs);
          for(const auto& spec:kSpecs)complete=complete&&item.values.count(spec.id);
        }
        if(complete){loaded=std::move(catalog);comparisonPresetIndex=active>=0?active+2:(active== -2?0:-1);}
      } else if(payload.empty())comparisonPresetIndex=0;
      cachedPresetReference=payload;refreshChoices();
    }
    if(comparisonPresetIndex>=2 && size_t(comparisonPresetIndex-2)<loaded.size()) {
      setEditedPresetIndex(matchesPreset(presetForIndex(comparisonPresetIndex),time)?-1:comparisonPresetIndex);
      selectPresetIfNeeded(comparisonPresetIndex);
    } else {
      setEditedPresetIndex(-1);
      selectPresetIfNeeded(comparisonPresetIndex==0&&matchesPreset(neutralPreset(),time)?0:1);
    }
    inPresetChange=false;
  }
  double value''',1)
s=s.replace('    selectPresetIfNeeded(comparisonPresetIndex);\n    endEditBlock();','    persistPresetReference(clean?nullptr:&p);\n    selectPresetIfNeeded(comparisonPresetIndex);\n    endEditBlock();',1)
s=s.replace('  OfxImageEffectHandle handle;','  OFX::StringParam* presetReference=nullptr;\n  std::string cachedPresetReference="UNINITIALIZED";\n  double lastPresetStateTime=0;\n  OfxImageEffectHandle handle;',1)
s=s.replace('  preset->setDefault(0);','''  preset->setDefault(0);
  // A loading action, never copied/restored as optical state.
  preset->setIsPersistant(false);
  preset->setAnimates(false);
  preset->setCanUndo(false);
  preset->setEvaluateOnChange(false);
  auto* reference=d.defineStringParam("presetReferenceState");
  reference->setDefault("");
  reference->setIsPersistant(true);
  reference->setAnimates(false);
  reference->setEvaluateOnChange(false);
  reference->getPropertySet().propSetInt(kOfxParamPropSecret,1);
''',1)
write(S/'src/ofx/LensDebaserPlugin.cpp',s)
# Reuse the exact passed optics, not experimental source or a regenerated shader.
accepted=json.loads((R/'build/integration/1.72/passed-build.json').read_text())
metal=Path(accepted['bundle'])/'Contents/Resources/LDBOptics.metallib'
assert hashlib.sha256(metal.read_bytes()).hexdigest()==accepted['integrated_shader_sha256']
(S/'build').mkdir(exist_ok=True)
lib=S/'build/LDBOptics.metallib'
if not lib.exists() or lib.read_bytes()!=metal.read_bytes():lib.write_bytes(metal.read_bytes())
# Prevent Make from rebuilding this immutable passed library.
mk=original('Makefile');a=mk.index('$(METAL_AIR):');b=mk.index('$(FIELD_PSF_AIR):',a)
mk=mk[:a]+'$(METAL_LIB):\n\t@test -f "$@"\n\n'+mk[b:]
mk+='\n$(OFX_BUILD)/LensDebaserPlugin.o: include/LDBPresetState.h\n'
write(S/'Makefile',mk)
info=plistlib.loads(subprocess.check_output(['git','show',REV+':resources/Info.plist'],cwd=R))
info['CFBundleName']='Lens Debaser Preset Copy Test';info['CFBundleIdentifier']='com.ldb.LensDebaser.PresetCopyTest';info['CFBundleVersion']='17201'
(S/'resources/Info.plist').write_bytes(plistlib.dumps(info))
subprocess.run(['make','ofx'],cwd=S,check=True)
bundle=S/'build/LensDebaser.ofx.bundle'
assert hashlib.sha256((bundle/'Contents/Resources/LDBOptics.metallib').read_bytes()).hexdigest()==accepted['integrated_shader_sha256']
subprocess.run([sys.executable,str(E/'test-state.py')],check=True)
out=E/'out';out.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='ldb-preset-copy-',dir='/private/tmp') as temp:
 staged=Path(temp)/'LensDebaserPresetCopyTest.ofx.bundle'
 subprocess.run(['ditto','--norsrc','--noextattr',str(bundle),str(staged)],check=True)
 executable=staged/'Contents/MacOS/LensDebaserPresetCopyTest.ofx'
 (staged/'Contents/MacOS/LensDebaser.ofx').rename(executable)
 staged_info=plistlib.loads((staged/'Contents/Info.plist').read_bytes())
 staged_info['CFBundleExecutable']=executable.name
 (staged/'Contents/Info.plist').write_bytes(plistlib.dumps(staged_info))
 subprocess.run(['xattr','-cr',str(staged)],check=True)
 subprocess.run(['codesign','--force','--deep','--sign','-',str(staged)],check=True)
 subprocess.run(['codesign','--verify','--deep','--strict',str(staged)],check=True)
 package=out/'LensDebaserPresetCopyTest.zip'
 subprocess.run(['ditto','-c','-k','--norsrc','--noextattr','--keepParent',str(staged),str(package)],check=True)
 assert executable.name==staged.name.removesuffix('.bundle')
 (out/'build.json').write_text(json.dumps({'label':'Lens Debaser Preset Copy Test','base_revision':REV,'optics_sha256':accepted['integrated_shader_sha256'],'plugin_sha256':hashlib.sha256(executable.read_bytes()).hexdigest(),'zip_sha256':hashlib.sha256(package.read_bytes()).hexdigest(),'status':'Compiled, codec tests passed, ad-hoc signature verified; Resolve check pending'},indent=2))
print('Built isolated Lens Debaser Preset Copy Test with exact passed 1.72 optics:',package)
subprocess.run([sys.executable,str(E/'verify-package.py')],check=True)
