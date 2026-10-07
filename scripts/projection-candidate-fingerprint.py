#!/usr/bin/env python3
"""Fingerprint only the candidate bundle's distributed files for install gating."""
from pathlib import Path
import hashlib,sys
bundle=Path(sys.argv[1]);digest=hashlib.sha256()
paths=[p for p in bundle.rglob('*') if p.is_file()]
if not paths:raise SystemExit('Missing candidate bundle')
for path in sorted(paths):
 digest.update(str(path.relative_to(bundle)).encode()+b'\0');digest.update(path.read_bytes())
print(digest.hexdigest())
