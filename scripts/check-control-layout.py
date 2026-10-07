#!/usr/bin/env python3
"""Check that the candidate presentation covers the complete existing descriptor set."""
from pathlib import Path
import re
repo=Path(__file__).resolve().parent.parent
source=(repo/'src/ofx/LensDebaserPlugin.cpp').read_text()
header=(repo/'include/LDBControlLayout.h').read_text()
spec=source.split('const DoubleSpec kSpecs[] = {',1)[1].split('struct Preset',1)[0]
doubles=set(re.findall(r'\{"([^"]+)",\s*"',spec))
# The remaining descriptors are explicitly defined choice/point/color/button controls.
function=source.split('void LensDebaserPluginFactory::describeInContext',1)[1]
other=set(re.findall(r'd\.define(?:Choice|Double2D|PushButton|Double)Param\("([^"]+)"',function))
other.update(re.findall(r'addColor\("([^"]+)"',function))
controls=set(re.findall(r'^  \{"([^"]+)",',header.split('inline constexpr Control controls[] = {',1)[1].split('};',1)[0],re.M))
assert controls==doubles|other,(sorted((doubles|other)-controls),sorted(controls-(doubles|other)))
assert 'LDBControlLayout::expandedGroups(configured)' in source
assert 'descriptor->setParent(*layoutGroups.at(control.group))' in source
print(f'PASS: all {len(controls)} controls covered; no missing or invented IDs; UI and expansion share the same hierarchy')
