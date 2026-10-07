#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
state="$repo/build/experiments/final-framing-candidate"
mkdir -p "$state"
flags='-DLDB_ENABLE_PROJECTION=1 -DLDB_ENABLE_FRAME_RELATIVE=1 -DLDB_FINAL_FRAMING_EXPERIMENT=1'
bundle="$state/LensDebaserFinalFramingTest.ofx.bundle"
make ofx FEATURE_FLAGS="$flags" BUILD="${state#"$repo/"}" METAL_AIR="$state/LDBOptics.air" METAL_LIB="$state/LDBOptics.metallib" OFX_BUILD="$state/objects" OFX_BUNDLE="$bundle" > "$state/build-log.txt" 2>&1
mv "$bundle/Contents/MacOS/LensDebaser.ofx" "$bundle/Contents/MacOS/LensDebaserFinalFramingTest.ofx"
/usr/bin/python3 - "$bundle" <<'PY'
import plistlib,sys
from pathlib import Path
p=Path(sys.argv[1])/'Contents/Info.plist';v=plistlib.loads(p.read_bytes());v.update(CFBundleName='Lens Debaser Final Framing Test',CFBundleIdentifier='com.ldb.LensDebaser.FinalFramingTest',CFBundleExecutable='LensDebaserFinalFramingTest.ofx');p.write_bytes(plistlib.dumps(v))
PY
staging="$(mktemp -d /private/tmp/ldb-final-framing.XXXXXX)"
signed="$staging/LensDebaserFinalFramingTest.ofx.bundle"
ditto --norsrc --noextattr "$bundle" "$signed"
xattr -cr "$signed"
codesign --force --deep --sign - "$signed"
codesign --verify --deep --strict "$signed"
printf '%s\n' "$signed" > "$state/signed-bundle-path.txt"
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun clang++ $flags -std=c++20 -fobjc-arc -arch arm64 -Iinclude tests/FactoryPresetReview.mm src/engine/LDBOpticsEngine.mm -o "$state/renderer" -framework Foundation -framework Metal -framework CoreGraphics -framework ImageIO
printf '%s\n' "$state" > build/integration/1.70/latest-final-framing-candidate-path.txt
printf 'Built separate final framing candidate: %s\n' "$state"
