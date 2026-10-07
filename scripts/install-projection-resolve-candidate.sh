#!/bin/bash
# Run after reviewing the validation HTML. Installs only the isolated test plug-in.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
if pgrep -x Resolve >/dev/null; then echo 'Fully quit DaVinci Resolve before installation.' >&2; exit 1; fi
build="$repo/build/experiments/projection-resolve-candidate"
[[ -f "$build/latest-validation-path.txt" ]] || { echo 'Run validate-projection-resolve-candidate.sh first.' >&2; exit 1; }
report="$(cat "$build/latest-validation-path.txt")"
case "$report" in "$repo"/outputs/engine-validation/passes/pass-103-projection-resolve-candidate-*) ;; *) echo 'Unexpected validation location.' >&2; exit 1;; esac
bundle="$report/LensDebaserProjectionTest.ofx.bundle"
[[ -f "$report/index.html" && -f "$report/validated-bundle.sha256" ]] || { echo 'Completed validation required.' >&2; exit 1; }
expected="$(cat "$report/validated-bundle.sha256")"
actual="$(/usr/bin/python3 scripts/projection-candidate-fingerprint.py "$bundle")"
[[ "$actual" == "$expected" ]] || { echo 'Validated candidate changed; refusing installation.' >&2; exit 1; }
identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist")"
[[ "$identifier" == 'com.ldb.LensDebaser.ProjectionTest' ]] || { echo 'Unexpected plug-in identity.' >&2; exit 1; }
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle/Contents/Info.plist")"
[[ "$executable" == 'LensDebaserProjectionTest.ofx' ]] || { echo 'Candidate executable name does not match bundle.' >&2; exit 1; }
# File-provider metadata can reappear after staging; strip it without changing file contents.
xattr -cr "$bundle"
codesign --verify --deep --strict "$bundle"
file "$bundle/Contents/MacOS/LensDebaserProjectionTest.ofx" | grep -q arm64
stamp="$(date +%Y%m%d-%H%M%S)-$$"
plugins='/Library/OFX/Plugins'
installed="$plugins/LensDebaserProjectionTest.ofx.bundle"
backup_root='/Library/Application Support/Lens Debaser Projection Test/Backups'
staged="$plugins/LensDebaserProjectionTest-staging-$stamp.ofx.bundle"
backup="$backup_root/LensDebaserProjectionTest-$stamp.ofx.bundle"
printf 'Installing the validated Projection Test beside Lens Debaser 1.69.\n'
sudo mkdir -p "$plugins" "$backup_root"
sudo ditto "$bundle" "$staged"
sudo xattr -cr "$staged"
sudo codesign --verify --deep --strict "$staged"
if sudo test -e "$installed"; then sudo mv "$installed" "$backup"; fi
if ! sudo mv "$staged" "$installed"; then
 if sudo test -e "$backup"; then sudo mv "$backup" "$installed"; fi
 echo "Installation failed. Any staging bundle is preserved at $staged" >&2
 exit 1
fi
examples="${HOME}/Library/Application Support/Lens Debaser Projection Test/Presets/Review-$stamp"
mkdir -p "$examples"
ditto "$bundle/Contents/Resources/Projection Examples" "$examples"
printf '\nInstalled: Lens Debaser Projection Test (LDB group).\nExamples: %s\nFully restart Resolve. Load one example; the other five appear in the Preset menu.\n' "$examples"
printf 'The existing LensDebaser.ofx.bundle and factory preset folder were not changed.\n'
