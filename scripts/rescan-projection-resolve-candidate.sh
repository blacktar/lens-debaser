#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
if pgrep -x Resolve >/dev/null; then echo 'Fully quit DaVinci Resolve before rescanning.' >&2; exit 1; fi
bundle='/Library/OFX/Plugins/LensDebaserProjectionTest.ofx.bundle'
test -f "$bundle/Contents/MacOS/LensDebaserProjectionTest.ofx"
codesign --verify --deep --strict "$bundle"
/usr/bin/python3 - <<'PY'
from pathlib import Path
import datetime,re,shutil,xml.etree.ElementTree as ET
root=Path.home()/'Library/Application Support/Blackmagic Design/DaVinci Resolve'
stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
backup=Path.cwd()/'outputs/engine-validation/cache-backups'/stamp
needle='/Library/OFX/Plugins/LensDebaserProjectionTest.ofx.bundle'
for name in ['OFXPluginCache.xml','OFXPluginCacheV2.xml']:
 path=root/name
 if not path.exists():continue
 original=path.read_text()
 ET.fromstring(original)
 removed=[0]
 def clean(match):
  if needle in match.group(0):removed[0]+=1;return ''
  return match.group(0)
 updated=re.sub(r'<bundle\b[^>]*>.*?</bundle>',clean,original,flags=re.S)
 ET.fromstring(updated)
 if removed[0]:
  backup.mkdir(parents=True,exist_ok=True);shutil.copy2(path,backup/name)
  path.write_text(updated)
 print(f'{name}: removed {removed[0]} Projection Test cache entries')
print(f'Backups, if needed: {backup}')
PY
printf '\nReopen Resolve so it scans Projection Test again.\n'
