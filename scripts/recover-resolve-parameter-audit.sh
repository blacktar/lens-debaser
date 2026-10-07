#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Recover the specific build that failed signing; no compilation or renders.
exec "$repo/scripts/finish-resolve-parameter-audit.sh" "$repo/outputs/experiments/resolve-parameter-audit-20261006-085405-62620"
