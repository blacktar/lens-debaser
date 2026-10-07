#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec /usr/bin/python3 "$repo/scripts/run-factory-review-1.70.py" "$@"
