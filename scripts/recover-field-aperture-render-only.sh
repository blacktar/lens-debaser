#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec /usr/bin/python3 "$repo/scripts/recover-field-aperture-render-only.py"
