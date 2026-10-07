#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
report="$repo/outputs/experiments/projection-angle-limits"
if [[ -e "$report" ]]; then echo "Preserving existing output: $report" >&2; exit 1; fi
[[ -f outputs/experiments/projection-models/index.html ]] || { echo 'Existing baseline required.' >&2; exit 1; }
mkdir -p "$report/images"
# Reuse passed display baselines; new zero-angle candidates validate the limit.
for image in outputs/experiments/projection-models/images/baseline-*.png; do cp "$image" "$report/images/"; done
/usr/bin/python3 scripts/audit-projection-angle-limits.py "$report" | tee "$report/mapping-log.txt"
build/ldb-guide-examples build/experiments/LDBOptics-projection-angle-limits.metallib "$repo" "$report/images" projection-angle-limits 2>&1 | tee "$report/render-log.txt"
/usr/bin/python3 scripts/build-projection-angle-report.py "$report" "$repo/outputs/experiments/projection-models" | tee "$report/report-log.txt"
for run in 1 2 3; do
 printf 'Angle benchmark run %s of 3\n' "$run"
 build/ldb-optics-benchmark build/LDBOptics.metallib build/experiments/LDBOptics-projection-angle-limits.metallib projection-angle-limits 2>&1 | tee "$report/benchmark-$run.txt"
done
/usr/bin/python3 scripts/build-projection-angle-report.py "$report" "$repo/outputs/experiments/projection-models" | tee "$report/report-log.txt"
open "$report/index.html"
printf 'Completed: %s/index.html\n' "$report"
