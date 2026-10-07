#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pointer="$repo/build/integration/1.70/latest-prepared-resolve-audit-path.txt"
if [[ ! -f "$pointer" ]]; then echo 'No completed prepared audit build found.' >&2; exit 1; fi
state="$(cat "$pointer")"
exec "$repo/scripts/finish-resolve-parameter-audit.sh" "$state"
