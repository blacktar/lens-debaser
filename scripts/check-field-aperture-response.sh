#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "Disabled after reported system freeze. Existing images are preserved; do not rerun this diagnostic yet." >&2
exit 1
exec /usr/bin/python3 "$repo/scripts/check-field-aperture-response.py"
