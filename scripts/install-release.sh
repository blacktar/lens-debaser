#!/bin/bash
set -euo pipefail

release_dir="$(cd "$(dirname "$0")" && pwd)"
source_bundle="$release_dir/LensDebaser.ofx.bundle"
source_presets="$release_dir/Presets"
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
if [[ ! -x "$source_bundle/Contents/MacOS/LensDebaser.ofx" ]]; then
  echo "ERROR: The compiled Lens Debaser plug-in is missing from this release." >&2
  exit 1
fi
if [[ ! -f "$source_bundle/Contents/Resources/LDBOptics.metallib" ]]; then
  echo "ERROR: The compiled Metal optics library is missing from this release." >&2
  exit 1
fi
if ! file "$source_bundle/Contents/MacOS/LensDebaser.ofx" | grep -q 'arm64'; then
  echo "ERROR: This release is not an Apple Silicon arm64 build." >&2
  exit 1
fi

bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$source_bundle/Contents/Info.plist")"
echo "Installing Lens Debaser $bundle_version for Apple Silicon…"
echo "Administrator approval is required to install an OpenFX plug-in for Resolve."
sudo mkdir -p "$plugin_dir" "$backup_dir"
trap cleanup_stage EXIT
cleanup_stage
sudo ditto "$source_bundle" "$staged_bundle"
sudo xattr -cr "$staged_bundle"
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
    echo "ERROR: Installation failed; the previous version was restored." >&2
  fi
  exit 1
fi
trap - EXIT

mkdir -p "$factory_preset_dir"
if [[ -d "$source_presets" ]]; then
  ditto "$source_presets" "$factory_preset_dir"
fi

echo
echo "Lens Debaser $bundle_version is installed."
echo "Fully quit and restart DaVinci Resolve before using it."
read -r -p "Press Return to close this window."
