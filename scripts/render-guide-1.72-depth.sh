#!/bin/bash
# Only the ten missing depth demo illustrations; no benchmarks or old rerenders.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
make build/ldb-factory-preset-review
/usr/bin/python3 scripts/render-guide-1.72-depth.py
