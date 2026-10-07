#!/bin/bash
# Installs exact passed inputs; never builds, renders or opens a report.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
if pgrep -x Resolve >/dev/null; then echo 'Fully quit Resolve before deployment.'; exit 1; fi
paths="$(/usr/bin/python3 - <<'PY'
from pathlib import Path
import json,subprocess
r=Path.cwd();p=r/'build/integration/1.72/passed-build.json'
assert p.exists(),'Run make validate first; integrated GPU validation is required'
d=json.loads(p.read_text());fp=lambda p:subprocess.check_output(['/usr/bin/python3',str(r/'scripts/projection-candidate-fingerprint.py'),str(p)],text=True).strip()
assert fp(Path(d['bundle']))==d['bundle_fingerprint'],'Passed bundle changed'
assert fp(r/'build/LensDebaser.ofx.bundle')==d['current_build_fingerprint'],'Current build differs from passed inputs'
assert fp(Path(d['factory']))==d['factory_fingerprint'],'Passed factory changed'
for folder in ['demonstrations','cinematic-lenses']:
 a={p.name:p.read_bytes() for p in (r/'presets'/folder).glob('*.ldbpreset')};b={p.name:p.read_bytes() for p in (Path(d['factory'])/folder).glob('*.ldbpreset')};assert a==b,'Factory changed after validation'
assert (r/'presets/README.md').read_bytes()==(Path(d['factory'])/'README.md').read_bytes()
print(d['bundle']);print(d['factory'])
PY
)"
bundle="$(printf '%s\n' "$paths" | sed -n '1p')"
factory="$(printf '%s\n' "$paths" | sed -n '2p')"
# File Provider may reattach Finder metadata in Documents after validation.
# Copy exact distribution bytes outside it; remove only extended attributes.
staging="$(mktemp -d /private/tmp/ldb-deploy-172.XXXXXX)"
clean_bundle="$staging/LensDebaser.ofx.bundle"
ditto --norsrc --noextattr "$bundle" "$clean_bundle"
xattr -cr "$clean_bundle"
original_fp="$(/usr/bin/python3 scripts/projection-candidate-fingerprint.py "$bundle")"
clean_fp="$(/usr/bin/python3 scripts/projection-candidate-fingerprint.py "$clean_bundle")"
if [[ "$original_fp" != "$clean_fp" ]]; then echo 'ERROR: Staged distribution differs from the passed snapshot.' >&2; exit 1; fi
codesign --verify --deep --strict "$clean_bundle"
LDB_VALIDATED_BUNDLE="$clean_bundle" LDB_VALIDATED_FACTORY="$factory" ./scripts/install-user.sh
