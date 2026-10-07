#!/usr/bin/env python3
"""Gate packaging on the exact validated, Resolve-approved binary."""
from pathlib import Path
import json,subprocess,hashlib
r=Path(__file__).resolve().parents[1]
d=json.loads((r/'build/integration/1.72/passed-build.json').read_text());a=json.loads((r/'docs/release-1.72-acceptance.json').read_text());bundle=Path(d['bundle'])
assert a['resolve_pass'] and a['build']==d['build']==172
fp=subprocess.check_output(['/usr/bin/python3',str(r/'scripts/projection-candidate-fingerprint.py'),str(bundle)],text=True).strip();assert fp==d['bundle_fingerprint'],'Passed bundle changed'
assert hashlib.sha256((bundle/'Contents/Resources/LDBOptics.metallib').read_bytes()).hexdigest()==a['shader_sha256']
old=json.loads((r/'presets/approved-1.70.json').read_text());new=json.loads((r/'presets/approved-1.72.json').read_text());assert all(new['files'][k]==v for k,v in old['files'].items()),'Previously approved optical presets changed'
assert len(new['files'])==133
for k,v in new['files'].items():assert (r/'presets'/k).read_text()==v,k
print(bundle)
