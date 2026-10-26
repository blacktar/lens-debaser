#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package="$repo/experiments/preset-copy/out/LensDebaserPresetCopyTest.zip"
proof="$repo/experiments/preset-copy/out/build.json"
if pgrep -x Resolve >/dev/null; then
  echo "Quit Resolve before installing the test plug-in."
  exit 1
fi
/usr/bin/python3 - "$package" "$proof" <<'PY'
import hashlib,json,sys
from pathlib import Path
package,proof=map(Path,sys.argv[1:]);data=json.loads(proof.read_text())
assert hashlib.sha256(package.read_bytes()).hexdigest()==data['zip_sha256'],'Test package changed; rebuild before installing'
PY
stage="$(mktemp -d /private/tmp/ldb-preset-copy-install.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
ditto -x -k --norsrc --noextattr "$package" "$stage"
bundle="$stage/LensDebaserPresetCopyTest.ofx.bundle"
xattr -cr "$bundle"
codesign --verify --deep --strict "$bundle"
target="/Library/OFX/Plugins/LensDebaserPresetCopyTest.ofx.bundle"
if [[ -d "$target" ]]; then
  backup="/Library/Application Support/Lens Debaser/Backups/PresetCopyTest-$(date +%Y%m%d-%H%M%S)"
  sudo mkdir -p "$backup"
  sudo mv "$target" "$backup/"
fi
sudo mkdir -p /Library/OFX/Plugins
sudo ditto --norsrc --noextattr "$bundle" "$target"
sudo xattr -cr "$target"
sudo find "$target" -type d -exec chmod 755 {} +
sudo find "$target" -type f -exec chmod 644 {} +
sudo chmod 755 "$target/Contents/MacOS/LensDebaserPresetCopyTest.ofx"
codesign --verify --deep --strict "$target"
/usr/bin/python3 "$repo/experiments/preset-copy/clear-failed-cache.py"
echo "Installed Lens Debaser Preset Copy Test alongside the released plug-in. Restart Resolve."
