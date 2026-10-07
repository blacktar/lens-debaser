#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/resources/Info.plist")"
release_name="Lens-Debaser-$version-Apple-Silicon"
release_root="$project_dir/releases"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/lens-debaser-release.XXXXXX")"
stage_dir="$temporary_root/$release_name"
archive="$release_root/$release_name.zip"
authoring_archive="$release_root/Lens-Debaser-Preset-Authoring-Kit-$version.zip"

cleanup() {
  rm -rf "$temporary_root"
}
trap cleanup EXIT

bundle="$project_dir/build/LensDebaser.ofx.bundle"
if [[ "$version" == "1.72" ]]; then
  bundle="$(/usr/bin/python3 "$project_dir/scripts/check-1.72-release.py")"
  make -C "$project_dir" presets
else
  make -C "$project_dir" ofx presets
fi
mkdir -p "$stage_dir/Presets" "$stage_dir/Preset Authoring Kit/examples" "$release_root"
ditto --norsrc --noextattr "$bundle" "$stage_dir/LensDebaser.ofx.bundle"
cp -R "$project_dir/presets/demonstrations" "$stage_dir/Presets/Demonstrations"
cp -R "$project_dir/presets/cinematic-lenses" "$stage_dir/Presets/Cinematic Lenses"
cp "$project_dir/presets/README.md" "$stage_dir/Presets/README.md"
cp "$project_dir/preset-authoring/AI-PRESET-AUTHORING.md" "$stage_dir/Preset Authoring Kit/README.md"
cp "$project_dir/preset-authoring/Lens-Debaser-Preset-Schema.json" "$stage_dir/Preset Authoring Kit/Lens-Debaser-Preset-Schema.json"
cp "$project_dir/preset-authoring/Clean-Slate-Template.ldbpreset" "$stage_dir/Preset Authoring Kit/Clean-Slate-Template.ldbpreset"
cp "$project_dir/preset-authoring/examples/"*.ldbpreset "$stage_dir/Preset Authoring Kit/examples/"
cp "$project_dir/scripts/install-release.sh" "$stage_dir/Install Lens Debaser.command"
chmod +x "$stage_dir/Install Lens Debaser.command"

cp "$project_dir/resources/Release-README.txt" "$stage_dir/README.txt"
cp "$project_dir/resources/THIRD-PARTY-NOTICES.txt" "$stage_dir/THIRD-PARTY-NOTICES.txt"

xattr -cr "$stage_dir/LensDebaser.ofx.bundle"
if [[ "$version" != "1.72" ]]; then codesign --force --deep --sign - "$stage_dir/LensDebaser.ofx.bundle"; fi
codesign --verify --deep --strict --verbose=2 "$stage_dir/LensDebaser.ofx.bundle"

rm -f "$archive" "$archive.sha256" "$authoring_archive"
# Distribution archives should contain only the files users need. Resource
# forks and extended attributes make ditto add a parallel __MACOSX tree of
# AppleDouble metadata, which is unnecessary for the signed OFX payload.
ditto -c -k --norsrc --noextattr --keepParent "$stage_dir" "$archive"
ditto -c -k --norsrc --noextattr --keepParent \
  "$stage_dir/Preset Authoring Kit" "$authoring_archive"
(cd "$release_root" && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
echo "Created $archive"
echo "Created $archive.sha256"
echo "Created $authoring_archive"
