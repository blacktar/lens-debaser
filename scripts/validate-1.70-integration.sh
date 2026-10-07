#!/bin/bash
# Explicit integrated validation; never installs or marks results passed.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
if rg -q '^FEATURE_FLAGS :=.*LDB_ENABLE_FRAME_RELATIVE=1' Makefile; then
 exec /usr/bin/python3 scripts/validate-effect-size-integration.py
fi
state="$repo/build/integration/1.70"
baseline="$(cat "$state/baseline-1.69-path.txt")"
old_library="$baseline/LensDebaser.ofx.bundle/Contents/Resources/LDBOptics.metallib"
test -f "$old_library"
make version-check ofx all build/ldb-guide-examples build/ldb-projection-integration-tests build/ldb-control-layout-tests
/usr/bin/python3 scripts/check-control-layout.py
build/ldb-control-layout-tests
build/ldb-projection-integration-tests --host-only
# Check unchanged factory files now; curate their content in the next phase.
/usr/bin/python3 scripts/audit-integration-factory-presets.py "$state/factory-audit.json"
bundle="$repo/build/LensDebaser.ofx.bundle"
xattr -cr "$bundle"
if ! codesign --verify --deep --strict "$bundle" 2>/dev/null; then
 codesign --force --deep --sign - "$bundle"
 xattr -cr "$bundle"
 codesign --verify --deep --strict "$bundle"
fi
fingerprint="$(/usr/bin/python3 scripts/projection-candidate-fingerprint.py "$bundle")"
report=''
if [[ -f "$state/latest-validation-path.txt" ]]; then
 previous="$(cat "$state/latest-validation-path.txt")"
 if [[ -f "$previous/validated-bundle.sha256" && "$fingerprint" == "$(cat "$previous/validated-bundle.sha256")" ]]; then
  if /usr/bin/python3 scripts/pass-1.70-integration.py --inputs-match "$previous"; then report="$previous"; fi
 fi
fi
if [[ -z "$report" ]]; then
 report="$repo/outputs/engine-validation/passes/pass-104-integration-1.70-$(date +%Y%m%d-%H%M%S)-$$"
 mkdir -p "$report/images"
 cp "$state/factory-audit.json" "$report/factory-audit.json"
 build/ldb-projection-integration-tests "$old_library" build/LDBOptics.metallib 2>&1 | tee "$report/projection-tests.txt"
 build/ldb-optics-tests build/LDBOptics.metallib 2>&1 | tee "$report/engine-tests.txt"
 build/ldb-guide-examples build/LDBOptics.metallib "$repo" "$report/images" projection-candidate-examples 2>&1 | tee "$report/render-log.txt"
 /usr/bin/python3 - "$repo" "$report" <<'PY'
from pathlib import Path
import shutil,sys
repo,report=map(Path,sys.argv[1:])
for preset in sorted((repo/'presets/experiments/projection-resolve-candidate').glob('*.ldbpreset')):
 fields=dict(line.split('=',1) for line in preset.read_text().splitlines() if '=' in line and not line.startswith('#'))
 model='equidistant' if fields['projectionModel']=='1' else 'stereographic'
 for source in ['iso','milano1']:
  shutil.copyfile(repo/f'outputs/experiments/projection-strength-sweep/{fields["projectionAmount"]}/images/{model}-geometry-{source}.png',report/f'images/passed-{preset.stem}-{source}.png')
for source in ['iso','milano1']:
 shutil.copyfile(repo/f'outputs/experiments/projection-models/images/baseline-geometry-{source}.png',report/f'images/baseline-{source}.png')
PY
 for run in 1 2 3; do
  build/ldb-optics-benchmark "$old_library" build/LDBOptics.metallib projection-candidate 2>&1 | tee "$report/benchmark-$run.txt"
 done
 /usr/bin/python3 scripts/build-projection-candidate-report.py "$report" 1.70
 /usr/bin/python3 scripts/build-control-layout-review.py "$report/control-layout-review.html" 1.70
 mkdir -p "$report/FactoryPresets"
 ditto "$repo/presets/demonstrations" "$report/FactoryPresets/demonstrations"
 ditto "$repo/presets/cinematic-lenses" "$report/FactoryPresets/cinematic-lenses"
 cp "$repo/presets/README.md" "$report/FactoryPresets/README.md"
 ditto "$bundle" "$report/LensDebaser.ofx.bundle"
 xattr -cr "$report/LensDebaser.ofx.bundle"
 codesign --verify --deep --strict "$report/LensDebaser.ofx.bundle"
 /usr/bin/python3 scripts/projection-candidate-fingerprint.py "$report/LensDebaser.ofx.bundle" > "$report/validated-bundle.sha256"
 printf '%s\n' "$report" > "$state/latest-validation-path.txt"
else
 printf 'Reusing completed validation for this exact bundle: %s\n' "$report"
fi
printf '\nIntegrated development build 1.70 validated. Factory-preset re-evaluation remains pending.\n'
open "$report/index.html"
printf '\nValidation is ready for review, not marked passed. Deployment is a separate step.\n'
