#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if pgrep -x Resolve >/dev/null; then echo 'Quit Resolve before installing the separate frame-relative test candidate.' >&2; exit 1; fi
state="$(cat "$repo/build/integration/1.70/latest-frame-relative-candidate-path.txt")"
bundle="$state/LensDebaserFrameRelativeTest.ofx.bundle"
staging="$(mktemp -d /private/tmp/ldb-frame-relative.XXXXXX)"
ditto --norsrc --noextattr "$bundle" "$staging/LensDebaserFrameRelativeTest.ofx.bundle"
xattr -cr "$staging/LensDebaserFrameRelativeTest.ofx.bundle"
codesign --force --deep --sign - "$staging/LensDebaserFrameRelativeTest.ofx.bundle"
codesign --verify --deep --strict "$staging/LensDebaserFrameRelativeTest.ofx.bundle"
destination='/Library/OFX/Plugins/LensDebaserFrameRelativeTest.ofx.bundle'
if [[ -e "$destination" ]]; then sudo mv "$destination" "$destination.previous-$(date +%Y%m%d-%H%M%S)-$$"; fi
sudo ditto --norsrc --noextattr "$staging/LensDebaserFrameRelativeTest.ofx.bundle" "$destination"
codesign --verify --deep --strict "$destination"
printf 'Installed separate Lens Debaser Frame Relative Test. Normal 1.70 and audit preserved.\n'
