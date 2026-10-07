#!/bin/bash
# Generate only the focused balanced-framing candidates; reuse existing baselines.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
report="$repo/outputs/experiments/projection-balanced"
renderer="$repo/build/ldb-guide-examples"
library="$repo/build/experiments/LDBOptics-projection.metallib"
baseline="$repo/outputs/experiments/projection-models"
for required in "$renderer" "$library" "$baseline/index.html"; do
    if [[ ! -f "$required" ]]; then
        printf 'Missing required existing artifact: %s\n' "$required" >&2
        exit 1
    fi
done
if [[ -e "$report" ]]; then
    printf 'Output already exists; preserving it: %s\n' "$report" >&2
    printf 'Review the existing output before requesting another render.\n' >&2
    exit 1
fi
mkdir -p "$report/images"
printf 'Rendering equidistant and stereographic with balanced framing...\n'
if ! "$renderer" "$library" "$repo" "$report/images" projection-balanced-validation 2>&1 | tee "$report/render-log.txt"; then
    printf 'Render failed. Log and any partial images were preserved in %s\n' "$report" >&2
    exit 1
fi
/usr/bin/python3 "$repo/scripts/build-projection-balanced-report.py" "$report" "$baseline" 2>&1 | tee "$report/report-log.txt"
printf '\nCompleted report: %s/index.html\n' "$report"
open "$report/index.html"
