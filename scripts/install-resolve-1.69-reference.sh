#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if pgrep -x Resolve >/dev/null; then echo 'Quit Resolve before installing the separate 1.69 reference.' >&2; exit 1; fi
state="$(cat "$repo/build/integration/1.70/latest-prepared-1.69-reference-path.txt")"
bundle="$state/LensDebaserReference169.ofx.bundle"
staging="$(mktemp -d /private/tmp/ldb-reference169.XXXXXX)"
ditto --norsrc --noextattr "$bundle" "$staging/LensDebaserReference169.ofx.bundle"
xattr -cr "$staging/LensDebaserReference169.ofx.bundle"
codesign --force --deep --sign - "$staging/LensDebaserReference169.ofx.bundle"
codesign --verify --deep --strict "$staging/LensDebaserReference169.ofx.bundle"
destination='/Library/OFX/Plugins/LensDebaserReference169.ofx.bundle'
if [[ -e "$destination" ]]; then sudo mv "$destination" "$destination.previous-$(date +%Y%m%d-%H%M%S)-$$"; fi
sudo ditto --norsrc --noextattr "$staging/LensDebaserReference169.ofx.bundle" "$destination"
codesign --verify --deep --strict "$destination"
printf 'Installed separate Lens Debaser 1.69 Reference. Normal 1.70 and audit preserved.\n'
