#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
build="$repo/build/experiments/projection-resolve-candidate"
validated="$(cat "$build/latest-validation-path.txt")"
test -f "$validated/validated-bundle.sha256"
actual="$(/usr/bin/python3 scripts/projection-candidate-fingerprint.py "$validated/LensDebaserProjectionTest.ofx.bundle")"
test "$actual" = "$(cat "$validated/validated-bundle.sha256")"
library="$validated/LensDebaserProjectionTest.ofx.bundle/Contents/Resources/LDBOptics.metallib"
test -f "$library"
# Build only the changed renderer; preserve the validated engine and bundle.
make -f scripts/Makefile.projection-candidate build/experiments/projection-resolve-candidate/ldb-guide-examples
report="$repo/outputs/experiments/projection-resolution-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$report/images"
cp "$validated/images/baseline-milano1.png" "$report/images/960-baseline.png"
cp "$validated/images/01-Projection-Equidistant-Subtle-milano1.png" "$report/images/960-projection.png"
"$build/ldb-guide-examples" "$library" "$repo" "$report/images" projection-resolution-comparison 2>&1 | tee "$report/render-log.txt"
/usr/bin/python3 scripts/build-projection-resolution-report.py "$report"
open "$report/index.html"
printf '\nReview: %s/index.html\n' "$report"
