#!/bin/bash
# Diagnostic installation only: separate identity, exact unchanged production shader.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
if pgrep -x Resolve >/dev/null; then echo 'Fully quit Resolve before installing the separate audit plug-in.' >&2; exit 1; fi
stamp="$(date +%Y%m%d-%H%M%S)-$$"
state="$repo/outputs/experiments/resolve-parameter-audit-$stamp"
mkdir -p "$state"
bundle="$state/LensDebaserParameterAudit.ofx.bundle"
flags="-DLDB_ENABLE_PROJECTION=1 -DLDB_RESOLVE_PARAMETER_AUDIT=1 -DLDB_RESOLVE_AUDIT_OUTPUT=\\\"$state\\\""
# Unique objects prevent contamination of normal or historical builds.
make ofx FEATURE_FLAGS="$flags" OFX_BUILD="$state/objects" OFX_BUNDLE="$bundle" 2>&1 | tee "$state/build-log.txt"
/usr/bin/python3 - "$bundle" <<'PY'
import plistlib,sys
from pathlib import Path
p=Path(sys.argv[1])/'Contents/Info.plist';v=plistlib.loads(p.read_bytes());v['CFBundleName']='Lens Debaser 1.70 Parameter Audit';v['CFBundleIdentifier']='com.ldb.LensDebaser.ParameterAudit';v['CFBundleExecutable']='LensDebaser.ofx';p.write_bytes(plistlib.dumps(v))
PY
# Match the OFX bundle/executable basename, as required for discovery.
mv "$bundle/Contents/MacOS/LensDebaser.ofx" "$bundle/Contents/MacOS/LensDebaserParameterAudit.ofx"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable LensDebaserParameterAudit.ofx' "$bundle/Contents/Info.plist"
cmp build/LDBOptics.metallib "$bundle/Contents/Resources/LDBOptics.metallib"
exec "$repo/scripts/finish-resolve-parameter-audit.sh" "$state"
