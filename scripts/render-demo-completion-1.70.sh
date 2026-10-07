#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if pgrep -x Resolve >/dev/null; then echo 'Quit Resolve before these Metal renders.' >&2; exit 1; fi
export LDB_FACTORY_REVIEW_PLAN="$repo/presets/experiments/factory-review-1.70-current-library"
export LDB_REVIEW_WIDTH=960
export LDB_REVIEW_BOUNDED_GUARD=1
export LDB_REVIEW_BENCHMARK_FRAMES=4
export LDB_REVIEW_BENCHMARK_RUNS=2
# Depth demos are intentionally excluded: the ordinary fixture is not a depth map.
exec /usr/bin/python3 "$repo/scripts/run-factory-review-1.70.py" completion
