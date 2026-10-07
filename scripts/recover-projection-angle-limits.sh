#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
old="$repo/outputs/experiments/projection-angle-limits"
report="$repo/outputs/experiments/projection-angle-limits-rechecked"
[[ -f "$old/render-audit.csv" ]] || { echo 'Original render audit required.' >&2; exit 1; }
[[ ! -e "$report" ]] || { echo "Preserving existing output: $report" >&2; exit 1; }
mkdir -p "$report/zero/images" "$report/images"
build/ldb-guide-examples build/experiments/LDBOptics-projection-angle-limits.metallib "$repo" "$report/zero/images" projection-angle-zero-recheck 2>&1 | tee "$report/zero/render-log.txt"
/usr/bin/python3 - "$old" "$report" <<'PY'
from pathlib import Path
import csv,sys,shutil
old,root=map(Path,sys.argv[1:])
with (old/'render-audit.csv').open() as f:
 reader=csv.DictReader(f);fields=reader.fieldnames;prior=list(reader)
with (root/'zero/render-audit.csv').open() as f: fresh=list(csv.DictReader(f))
assert len(prior)==1020 and len(fresh)==60,'Unexpected audit row count'
assert all('-a0-' in r['image'] for r in fresh),'Recovery should render only zero angle'
assert all(int(r['nonfinite_components'])==0 and float(r['zero_limit_max_error'])<=1e-6 for r in fresh),'Zero-angle recheck failed'
replacements={r['image']:r for r in fresh}
assert len(replacements)==60 and set(replacements)=={r['image'] for r in prior if '-a0-' in r['image']}
merged=[replacements.get(r['image'],r) for r in prior]
assert all(int(r['nonfinite_components'])==0 for r in merged),'Original nonfinite results require further diagnosis'
for image in (old/'images').glob('*.png'):
 target=root/'zero/images'/image.name if image.name in replacements else image
 assert target.is_file(),f'Missing image: {target}'
 (root/'images'/image.name).symlink_to(target.resolve())
with (root/'render-audit.csv').open('w') as f:
 writer=csv.DictWriter(f,fieldnames=fields);writer.writeheader();writer.writerows(merged)
shutil.copyfile(old/'mapping-audit.csv',root/'mapping-audit.csv')
(root/'recovery-note.txt').write_text('Original pass preserved. 960 nonzero candidates reused; 60 zero-angle candidates rerendered. Zero projection now bypasses coordinate reconstruction. Identity references use the same forced sampling path (distortionK1=1e-12) as candidates. This removes an unfair neutral-copy versus resampling comparison. GPU identity remains subject to the 1e-6 tolerance. Linked images depend on the preserved original and zero directories.\n')
print('Merged 60 rechecked zero-angle cases with 960 unchanged candidates.')
PY
/usr/bin/python3 scripts/build-projection-angle-report.py "$report" "$repo/outputs/experiments/projection-models" | tee "$report/report-log.txt"
for run in 1 2 3; do
 printf 'Angle benchmark run %s of 3\n' "$run"
 build/ldb-optics-benchmark build/LDBOptics.metallib build/experiments/LDBOptics-projection-angle-limits.metallib projection-angle-limits 2>&1 | tee "$report/benchmark-$run.txt"
done
/usr/bin/python3 scripts/build-projection-angle-report.py "$report" "$repo/outputs/experiments/projection-models" | tee "$report/report-log.txt"
open "$report/index.html"
printf 'Completed: %s/index.html\n' "$report"
