#!/bin/bash
# Install only a previously reviewed/passed build. No build, GPU work or report UI.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
paths="$(/usr/bin/python3 scripts/pass-1.70-integration.py --check)"
bundle="$(printf '%s\n' "$paths" | sed -n '1p')"
factory="$(printf '%s\n' "$paths" | sed -n '2p')"
if pgrep -x Resolve >/dev/null; then echo 'Fully quit Resolve before deployment.' >&2; exit 1; fi
xattr -cr "$bundle"
codesign --verify --deep --strict "$bundle"
LDB_VALIDATED_BUNDLE="$bundle" LDB_VALIDATED_FACTORY="$factory" ./scripts/install-user.sh
