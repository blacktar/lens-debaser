#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
logs="$repo/outputs/experiments/projection-balanced-benchmarks-$(date +%Y%m%d-%H%M%S)-$$"
mkdir "$logs"
for run in 1 2 3 4 5; do
 printf 'Benchmark run %s of 5\n' "$run"
 build/ldb-optics-benchmark build/LDBOptics.metallib build/experiments/LDBOptics-projection.metallib projection-balanced 2>&1 | tee "$logs/run-$run.txt"
done
printf 'Saved benchmark logs: %s\n' "$logs"
