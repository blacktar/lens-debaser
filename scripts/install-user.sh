#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
source_bundle="$project_dir/build/LensDebaser.ofx.bundle"
plugin_dir="/Library/OFX/Plugins"
backup_dir="/Library/Application Support/Lens Debaser/Backups"
factory_preset_dir="${HOME}/Library/Application Support/Lens Debaser/Presets"
installed_bundle="$plugin_dir/LensDebaser.ofx.bundle"
staged_bundle="$plugin_dir/.LensDebaser.ofx.bundle.installing.$$"
timestamp="$(date +%Y%m%d-%H%M%S)"

cleanup_stage() {
  if [[ -d "$staged_bundle" ]]; then
    sudo rm -rf "$staged_bundle"
  fi
}

if pgrep -x "Resolve" >/dev/null; then
  echo "ERROR: Fully quit DaVinci Resolve before installing Lens Debaser." >&2
  exit 1
fi

echo "Building Lens Debaser…"
make -C "$project_dir" ofx

if [[ ! -x "$source_bundle/Contents/MacOS/LensDebaser.ofx" ]]; then
  echo "ERROR: Lens Debaser executable was not created." >&2
  exit 1
fi
if [[ ! -f "$source_bundle/Contents/Resources/LDBOptics.metallib" ]]; then
  echo "ERROR: Metal optics library is missing from the bundle." >&2
  exit 1
fi
if ! file "$source_bundle/Contents/MacOS/LensDebaser.ofx" | grep -q 'arm64'; then
  echo "ERROR: Lens Debaser is not an Apple-silicon arm64 bundle." >&2
  exit 1
fi
if ! nm -gU "$source_bundle/Contents/MacOS/LensDebaser.ofx" | grep -q '_OfxGetNumberOfPlugins' ||
   ! nm -gU "$source_bundle/Contents/MacOS/LensDebaser.ofx" | grep -q '_OfxGetPlugin'; then
  echo "ERROR: Required OpenFX entry points are missing." >&2
  exit 1
fi
bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_bundle/Contents/Info.plist")"
bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$source_bundle/Contents/Info.plist")"
if [[ "$bundle_identifier" != "com.ldb.LensDebaser" || -z "$bundle_version" ]]; then
  echo "ERROR: Lens Debaser bundle metadata is invalid." >&2
  exit 1
fi

echo "Installing into Resolve's system OFX directory (administrator password may be requested)…"
sudo mkdir -p "$plugin_dir"
sudo mkdir -p "$backup_dir"
trap cleanup_stage EXIT

# Older installer revisions left backups beside active OFX bundles, where
# Resolve attempted to scan them as additional plug-ins.
for old_backup in "$plugin_dir"/LensDebaser.ofx.bundle.backup-*; do
  if sudo test -e "$old_backup"; then
    sudo mv "$old_backup" "$backup_dir/"
  fi
done
cleanup_stage
sudo ditto "$source_bundle" "$staged_bundle"

# File Provider and Finder may attach metadata while copying. OFX bundles must
# be cleaned before their final local signature is created.
sudo xattr -cr "$staged_bundle"
sudo xattr -d com.apple.FinderInfo "$staged_bundle" 2>/dev/null || true
sudo xattr -d 'com.apple.fileprovider.fpfs#P' "$staged_bundle" 2>/dev/null || true
sudo codesign --force --deep --sign - "$staged_bundle"
sudo codesign --verify --deep --strict --verbose=2 "$staged_bundle"

if sudo test -e "$installed_bundle"; then
  backup_bundle="$backup_dir/LensDebaser-$timestamp.ofx.bundle"
  sudo mv "$installed_bundle" "$backup_bundle"
  echo "Previous installation saved as: $backup_bundle"
fi

if ! sudo mv "$staged_bundle" "$installed_bundle"; then
  if [[ -n "${backup_bundle:-}" ]] && sudo test -e "$backup_bundle"; then
    sudo mv "$backup_bundle" "$installed_bundle"
    echo "ERROR: Installation failed; previous Lens Debaser installation was restored." >&2
  fi
  exit 1
fi
trap - EXIT

echo "Installed: $installed_bundle"
echo "Version: $bundle_version"
sudo codesign --verify --deep --strict --verbose=2 "$installed_bundle"
mkdir -p "$factory_preset_dir/Demonstrations" "$factory_preset_dir/Cinematic Lenses"
ditto "$project_dir/presets/demonstrations" "$factory_preset_dir/Demonstrations"
ditto "$project_dir/presets/cinematic-lenses" "$factory_preset_dir/Cinematic Lenses"
cp "$project_dir/presets/README.md" "$factory_preset_dir/README.md"
echo "External presets: $factory_preset_dir"
echo "Fully quit and restart DaVinci Resolve."
