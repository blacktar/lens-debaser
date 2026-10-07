#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if pgrep -x Resolve >/dev/null; then echo 'Fully quit Resolve first.' >&2; exit 1; fi
state="${1:?Expected the completed audit build directory}"
bundle="$state/LensDebaserParameterAudit.ofx.bundle"
test -f "$bundle/Contents/MacOS/LensDebaserParameterAudit.ofx"
# Sign outside the Documents/File Provider tree; omit inherited resource forks.
staging_root="$(mktemp -d /private/tmp/ldb-resolve-audit.XXXXXX)"
staged="$staging_root/LensDebaserParameterAudit.ofx.bundle"
ditto --norsrc --noextattr "$bundle" "$staged"
xattr -cr "$staged"
codesign --force --deep --sign - "$staged"
codesign --verify --deep --strict "$staged"
cmp "$bundle/Contents/Resources/LDBOptics.metallib" "$staged/Contents/Resources/LDBOptics.metallib"
printf '%s\n' "$staged" > "$state/signed-bundle-path.txt"
destination='/Library/OFX/Plugins/LensDebaserParameterAudit.ofx.bundle'
stamp="$(date +%Y%m%d-%H%M%S)-$$"
if [[ -e "$destination" ]]; then sudo mv "$destination" "$destination.previous-$stamp"; fi
sudo ditto --norsrc --noextattr "$staged" "$destination"
codesign --verify --deep --strict "$destination"
printf '%s\n' "$state" > "$repo/build/integration/1.70/latest-resolve-audit-path.txt"
printf '\nInstalled Lens Debaser 1.70 Parameter Audit.\n'
printf 'Substitute the audit effect on the same input node, load original 26, and view a frame.\n'
printf 'Then run ./scripts/read-resolve-parameter-audit.sh\n'
