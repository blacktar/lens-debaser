#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/resources/Info.plist")"
release_name="Lens-Debaser-$version-Apple-Silicon"
release_root="$project_dir/releases"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/lens-debaser-release.XXXXXX")"
stage_dir="$temporary_root/$release_name"
archive="$release_root/$release_name.zip"

cleanup() {
  rm -rf "$temporary_root"
}
trap cleanup EXIT

make -C "$project_dir" ofx presets
mkdir -p "$stage_dir/Presets" "$release_root"
ditto "$project_dir/build/LensDebaser.ofx.bundle" "$stage_dir/LensDebaser.ofx.bundle"
cp -R "$project_dir/presets/demonstrations" "$stage_dir/Presets/Demonstrations"
cp -R "$project_dir/presets/cinematic-lenses" "$stage_dir/Presets/Cinematic Lenses"
cp "$project_dir/presets/README.md" "$stage_dir/Presets/README.md"
cp "$project_dir/scripts/install-release.sh" "$stage_dir/Install Lens Debaser.command"
chmod +x "$stage_dir/Install Lens Debaser.command"

cp "$project_dir/resources/Release-README.txt" "$stage_dir/README.txt"
cp "$project_dir/resources/THIRD-PARTY-NOTICES.txt" "$stage_dir/THIRD-PARTY-NOTICES.txt"

xattr -cr "$stage_dir/LensDebaser.ofx.bundle"
codesign --force --deep --sign - "$stage_dir/LensDebaser.ofx.bundle"
codesign --verify --deep --strict --verbose=2 "$stage_dir/LensDebaser.ofx.bundle"

rm -f "$archive" "$archive.sha256"
ditto -c -k --sequesterRsrc --keepParent "$stage_dir" "$archive"
(cd "$release_root" && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
echo "Created $archive"
echo "Created $archive.sha256"
