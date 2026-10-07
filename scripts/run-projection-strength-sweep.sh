#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
report="$repo/outputs/experiments/projection-strength-sweep"
if [[ -e "$report" ]]; then
 printf 'Preserving existing output: %s\n' "$report" >&2
 exit 1
fi
[[ -f outputs/experiments/projection-balanced/index.html ]] || { echo 'Completed balanced comparison required.' >&2; exit 1; }
mkdir -p "$report"
cp -R outputs/experiments/projection-balanced "$report/45"
for amount in 20 70; do
 mkdir -p "$report/$amount/images"
 build/ldb-guide-examples build/experiments/LDBOptics-projection.metallib "$repo" "$report/$amount/images" "projection-balanced-$amount" 2>&1 | tee "$report/$amount/render-log.txt"
done
/usr/bin/python3 scripts/build-projection-strength-report.py "$report" | tee "$report/report-log.txt"
./scripts/record-projection-balanced-benchmarks.sh
open "$report/index.html"
