#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if pgrep -x Resolve >/dev/null; then echo 'Quit Resolve first.'; exit 1; fi
state="$(cat "$repo/build/integration/1.70/latest-final-framing-candidate-path.txt")"
signed="$(cat "$state/signed-bundle-path.txt")"
codesign --verify --deep --strict "$signed"
destination='/Library/OFX/Plugins/LensDebaserFinalFramingTest.ofx.bundle'
if [[ -e "$destination" ]]; then sudo mv "$destination" "$destination.previous-$(date +%Y%m%d-%H%M%S)"; fi
sudo ditto --norsrc --noextattr "$signed" "$destination"
codesign --verify --deep --strict "$destination"
printf 'Installed separate Lens Debaser Final Framing Test. Normal1.70 preserved.\nPresets: %s\n' "$repo/presets/experiments/final-framing/resolve-test"
