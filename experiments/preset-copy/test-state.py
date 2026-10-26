#!/usr/bin/env python3
"""Compile and exercise the exact metadata codec without a Resolve/Metal dependency."""
from pathlib import Path
import subprocess
E=Path(__file__).resolve().parent;R=E.parents[1];O=E/'codec-tests';O.mkdir(exist_ok=True)
s=subprocess.check_output(['git','show','30902a7:src/ofx/LensDebaserPlugin.cpp'],cwd=R,text=True)
a=s.index('struct Preset {');b=s.index('\n};',a)+3
preamble='''#include <string>
#include <sstream>
#include <iomanip>
#include <unordered_map>
#include <map>
#include <array>
#include <vector>
#include <cmath>
#include <cassert>
#include <iostream>
'''
checks=r'''
int main(){
 Preset a;a.name=R"(Hawk / Cooke \"quoted\" reference – edited)";
 for(int i=0;i<160;i++)a.values["control"+std::to_string(i)]=i*.00123456789012345;
 a.values["tiny"]=-1e-15;a.values["extreme"]=1e18;
 a.center={.32,.71};a.fieldCenter={.4,.6};a.transmission={1,.9,.8};a.glare={.2,.7,1.2};
 a.nearFocus={1,.2,.3};a.farFocus={.2,1,.5};a.anamorphicFlare={.1,.3,.8};a.anamorphicFlareGhost={.8,.2,.9};
 a.apertureShape=2;a.apertureBladeCount=11;a.depthMode=4;a.captureGate=7;a.prismDistribution=3;a.opticalDriftMode=2;
 a.effectSize=1;a.projectionModel=2;a.projectionFraming=2;a.finalFramingMode=1;
 std::string saved=encodePresetState(a);Preset b;
 assert(decodePresetState(saved,b));assert(encodePresetState(b)==saved);
 // Copy carries the original reference independently of edited controls or any file.
 Preset edited=a;edited.values["control3"]+=.25;
 Preset copiedReference;assert(decodePresetState(saved,copiedReference));
 assert(copiedReference.values==a.values&&copiedReference.values!=edited.values);
 for(size_t n=0;n<saved.size()/2;n+=17){Preset unchanged=a;assert(!decodePresetState(saved.substr(0,n),unchanged));assert(encodePresetState(unchanged)==saved);}
 Preset untouched=a;
 assert(!decodePresetState("",untouched));assert(!decodePresetState("CUSTOM",untouched));
 assert(!decodePresetState(saved+"unexpected",untouched));
 assert(!decodePresetState(std::string(131073,'x'),untouched));
 auto duplicate=saved;auto at=duplicate.find("\"control1\"");assert(at!=std::string::npos);
 duplicate.replace(at,10,"\"control0\"");assert(!decodePresetState(duplicate,untouched));
 auto future=saved;future.replace(future.find(" 1 "),3," 2 ");assert(!decodePresetState(future,untouched));
 assert(encodePresetState(untouched)==saved);
 std::vector<Preset> catalog={a,edited,a};catalog[2].name="Other folder member";
 auto library=encodePresetLibrary(catalog,1);std::vector<Preset> restored;int active=-1;
 assert(decodePresetLibrary(library,restored,active));assert(active==1&&restored.size()==3);
 assert(encodePresetLibrary(restored,active)==library);
 for(int selection:{-2,-1,0,2}){auto state=encodePresetLibrary(catalog,selection);assert(decodePresetLibrary(state,restored,active)&&active==selection);}
 assert(decodePresetLibrary(library,restored,active));
 assert(!decodePresetLibrary(library+"bad",restored,active));
 assert(active==1&&restored.size()==3);
 std::cout<<"PASS: full loaded catalogue/selection round trip;  exact round trip of every reference field, edited/reference separation, copy without preset files, and invalid/truncated/duplicate/future payload rejection ("<<saved.size()<<" bytes).\n";
}
'''
source=O/'tests.cpp';source.write_text(preamble+s[a:b]+'\n#include "PresetState.h"\n'+checks)
subprocess.run(['env','DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer','xcrun','clang++','-std=c++20','-DLDB_ENABLE_FRAME_RELATIVE=1','-DLDB_ENABLE_PROJECTION=1','-DLDB_ENABLE_FINAL_FRAMING=1','-I'+str(E),str(source),'-o',str(O/'tests')],check=True)
subprocess.run([str(O/'tests')],check=True)
