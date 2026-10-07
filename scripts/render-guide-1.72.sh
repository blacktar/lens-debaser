#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
if pgrep -x Resolve >/dev/null; then echo 'Quit Resolve before rendering guide examples.'; exit 1; fi
make build/ldb-factory-preset-review
/usr/bin/python3 scripts/render-guide-1.72.py
/usr/bin/python3 scripts/render-guide-1.72-depth.py
