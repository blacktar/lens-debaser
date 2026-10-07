#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LDB_FACTORY_REVIEW_PLAN="$repo/presets/experiments/cinematic-strength-regression-1.70"
exec /usr/bin/python3 "$repo/scripts/run-factory-review-1.70.py" regression
