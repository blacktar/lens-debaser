#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
build="$repo/build/experiments/projection-resolve-candidate"
baseline_library="$repo/build/LDBOptics.metallib"
if [[ -f "$repo/build/integration/1.70/baseline-1.69-path.txt" ]]; then
 preserved="$(cat "$repo/build/integration/1.70/baseline-1.69-path.txt")"
 baseline_library="$preserved/LensDebaser.ofx.bundle/Contents/Resources/LDBOptics.metallib"
fi
test -f "$baseline_library"
make -f scripts/Makefile.projection-candidate projection-candidate
report="$repo/outputs/engine-validation/passes/pass-103-projection-resolve-candidate-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$report/images"
"$build/ldb-projection-candidate-tests" "$baseline_library" "$build/LDBOptics.metallib" 2>&1 | tee "$report/projection-tests.txt"
"$build/ldb-optics-tests" "$build/LDBOptics.metallib" 2>&1 | tee "$report/engine-tests.txt"
"$build/ldb-guide-examples" "$build/LDBOptics.metallib" "$repo" "$report/images" projection-candidate-examples 2>&1 | tee "$report/render-log.txt"
/usr/bin/python3 - "$repo" "$report" <<'PY'
from pathlib import Path
import shutil,sys
repo,root=map(Path,sys.argv[1:])
for preset in sorted((repo/'presets/experiments/projection-resolve-candidate').glob('*.ldbpreset')):
 fields=dict(line.split('=',1) for line in preset.read_text().splitlines() if '=' in line and not line.startswith('#'))
 model='equidistant' if fields['projectionModel']=='1' else 'stereographic'
 for source in ['iso','milano1']:
  passed=repo/f'outputs/experiments/projection-strength-sweep/{fields["projectionAmount"]}/images/{model}-geometry-{source}.png'
  shutil.copyfile(passed,root/f'images/passed-{preset.stem}-{source}.png')
for source in ['iso','milano1']:
 shutil.copyfile(repo/f'outputs/experiments/projection-models/images/baseline-geometry-{source}.png',root/f'images/baseline-{source}.png')
PY
for run in 1 2 3; do
 "$build/ldb-optics-benchmark" "$baseline_library" "$build/LDBOptics.metallib" projection-candidate 2>&1 | tee "$report/benchmark-$run.txt"
done
/usr/bin/python3 scripts/build-projection-candidate-report.py "$report"
# Preserve the exact tested candidate rather than installing a later rebuild.
ditto "$build/LensDebaserProjectionTest.ofx.bundle" "$report/LensDebaserProjectionTest.ofx.bundle"
xattr -cr "$report/LensDebaserProjectionTest.ofx.bundle"
codesign --verify --deep --strict "$report/LensDebaserProjectionTest.ofx.bundle"
/usr/bin/python3 scripts/projection-candidate-fingerprint.py "$report/LensDebaserProjectionTest.ofx.bundle" > "$report/validated-bundle.sha256"
printf '%s\n' "$report" > "$build/latest-validation-path.txt"
open "$report/index.html"
printf '\nValidation completed; no plug-in installed. Review: %s/index.html\n' "$report"
