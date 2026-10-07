#!/bin/bash
# Host presentation update: reuse the tested shader and preserve previous passes.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
build="$repo/build/experiments/projection-resolve-candidate"
previous="$(cat "$build/latest-validation-path.txt")"
case "$previous" in "$repo"/outputs/engine-validation/passes/pass-103-projection-resolve-candidate-*) ;; *) echo 'Unexpected validated pass path.' >&2; exit 1;; esac
expected="$(cat "$previous/validated-bundle.sha256")"
actual="$(/usr/bin/python3 scripts/projection-candidate-fingerprint.py "$previous/LensDebaserProjectionTest.ofx.bundle")"
test "$actual" = "$expected"
make -f scripts/Makefile.projection-candidate projection-candidate projection-control-layout-check
"$build/ldb-projection-candidate-tests" --host-only
cmp "$previous/LensDebaserProjectionTest.ofx.bundle/Contents/Resources/LDBOptics.metallib" "$build/LensDebaserProjectionTest.ofx.bundle/Contents/Resources/LDBOptics.metallib"
report="$repo/outputs/engine-validation/passes/pass-103-projection-resolve-candidate-$(date +%Y%m%d-%H%M%S)-control-layout-$$"
/usr/bin/python3 - "$previous" "$report" "$build" <<'PY'
from pathlib import Path
import shutil,sys
previous,report,build=map(Path,sys.argv[1:])
shutil.copytree(previous,report)
bundle=report/'LensDebaserProjectionTest.ofx.bundle'
shutil.rmtree(bundle);shutil.copytree(build/bundle.name,bundle)
(report/'control-layout-update.txt').write_text('Host presentation update only: complete candidate label/group/order audit, ancestor expansion and descriptor ordering. Control inventory/hierarchy, host-only mapping, compilation and signature checks passed. Previous GPU results and renders reused because the shader is unchanged. Resolve layout verification pending. IDs, values, presets and DSP unchanged.\n')
p=report/'index.html';s=p.read_text();s=s.replace('<main>','<main><p>Control layout update: rendering is unchanged. Previous GPU results and images are reused. The revised host labels, grouping and order require Resolve review before integration.</p>',1);p.write_text(s)
PY
xattr -cr "$report/LensDebaserProjectionTest.ofx.bundle"
codesign --verify --deep --strict "$report/LensDebaserProjectionTest.ofx.bundle"
/usr/bin/python3 scripts/projection-candidate-fingerprint.py "$report/LensDebaserProjectionTest.ofx.bundle" > "$report/validated-bundle.sha256"
/usr/bin/python3 scripts/build-control-layout-review.py "$report/control-layout-review.html"
printf '%s\n' "$report" > "$build/latest-validation-path.txt"
printf '\nPrepared revised control layout: %s\nQuit Resolve, then run: make deploy PROJECTION_CANDIDATE=1\n' "$report"
