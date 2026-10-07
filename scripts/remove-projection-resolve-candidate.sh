#!/bin/bash
# Reversible removal of only the test plug-in; preserve it in the test backups.
set -euo pipefail
if pgrep -x Resolve >/dev/null; then echo 'Fully quit Resolve first.' >&2; exit 1; fi
installed='/Library/OFX/Plugins/LensDebaserProjectionTest.ofx.bundle'
[[ -d "$installed" ]] || { echo 'Projection Test is not installed.'; exit 0; }
identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$installed/Contents/Info.plist")"
[[ "$identifier" == 'com.ldb.LensDebaser.ProjectionTest' ]] || { echo 'Unexpected identity; no changes made.' >&2; exit 1; }
backup_root='/Library/Application Support/Lens Debaser Projection Test/Backups'
backup="$backup_root/Removed-$(date +%Y%m%d-%H%M%S)-$$.ofx.bundle"
sudo mkdir -p "$backup_root"
sudo mv "$installed" "$backup"
printf 'Projection Test moved to %s\nLens Debaser 1.69 remains installed.\n' "$backup"
