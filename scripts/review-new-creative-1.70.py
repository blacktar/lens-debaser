#!/usr/bin/env python3
"""Render and benchmark twelve new recipes without a comparison baseline."""
from pathlib import Path
import argparse, hashlib, json, os, re, shutil, subprocess

R = Path(__file__).resolve().parent.parent
PLAN = R/'presets/experiments/new-creative-1.70'
WORK = R/'outputs/experiments/new-creative-1.70-working'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def available_memory():
    # macOS's system estimate includes reclaimable memory; low raw free-page
    # counts alone do not establish that the machine cannot run a small case.
    query = subprocess.run(['memory_pressure', '-Q'], capture_output=True, text=True)
    total = re.search(r'The system has (\d+)', query.stdout)
    percent = re.search(r'System-wide memory free percentage:\s*(\d+)%', query.stdout)
    if query.returncode == 0 and total and percent:
        return int(total.group(1))*int(percent.group(1))/100, 'macOS system estimate'
    vm = subprocess.check_output(['vm_stat'], text=True)
    page = int(re.search(r'page size of (\d+) bytes', vm).group(1))
    counts = {k:int(v) for k,v in re.findall(r'^([^:]+):\s+(\d+)\.', vm, re.M)}
    return sum(counts.get(k,0) for k in ('Pages free','Pages inactive','Pages speculative'))*page, 'fallback page count'

def assemble(manifest):
    import html, statistics
    esc = html.escape
    source = WORK/'images/unprocessed-milano1.png'
    original = R/'outputs/experiments/optical-drift-presets/before-milano1.png'
    import struct
    assert struct.unpack('>II', original.read_bytes()[16:24]) == (960,455)
    if not source.exists() or sha(source) != sha(original): shutil.copy2(original, source)
    cards = []
    for row in manifest['rows']:
        prefix = WORK/'images'/(row['id']+'--milano1')
        metrics = Path(str(prefix)+'-metrics.json')
        snapshot = WORK/'inputs'/row['id']/'candidate.ldbpreset'
        current = R/row['candidate']
        if not metrics.exists() or not json.loads(metrics.read_text()).get('standalone') or not snapshot.exists() or sha(snapshot) != sha(current):
            cards.append('<article><h2>'+esc(row['label'])+'</h2><p>'+esc(row['rationale'])+'</p><p>Current recipe not rendered yet; any earlier output is excluded.</p></article>')
            continue
        data = json.loads(metrics.read_text())
        if not data.get('standalone'): continue
        validate(prefix)
        reference = R/row['visual_previous'] if row.get('visual_previous') else source
        reference_label = 'Previous creative version' if row.get('visual_previous') else 'Unprocessed image'
        if row.get('visual_previous'): assert sha(reference) == row['visual_previous_sha256']
        timing = ''
        for key,label in [('gpu','GPU'),('wall','Wall')]:
            times = [run[key] for run in data['runs']]
            timing += f'<tr><td>{label}</td><td>{statistics.median(times):.3f} ms</td><td>{min(times):.3f}–{max(times):.3f} ms</td></tr>'
        cards.append('<article class="new-preset"><h2>'+esc(row['label'])+' · iPhone scene1</h2><p>'+esc(row['rationale'])+'</p><div class="compare"><img src="'+Path(str(prefix)+'-render.png').as_uri()+'"><div class="before"><img src="'+reference.as_uri()+'"></div><span class="divider"></span><span class="label left">'+esc(reference_label)+'</span><span class="label right">New preset</span><input type="range" min="0" max="100" value="50" aria-label="Compare reference image with '+esc(row['label'])+'"></div><p>960×455 · finite components: PASS · two runs of four timed frames after four warm-ups per run.</p><table><tr><th>Timing</th><th>Median per frame</th><th>Run range</th></tr>'+timing+'</table></article>')
    count = sum('class="new-preset"' in card for card in cards)
    style = (R/'scripts/build-optical-drift-preset-report.py').read_text().split('<style>',1)[1].split('</style>',1)[0].replace('{{','{').replace('}}','}')
    style += 'table{width:100%;border-collapse:collapse}td,th{text-align:left;padding:9px;border-bottom:1px solid #303840}'
    doc = '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Lens Debaser · New Creative Presets</title><style>'+style+'</style><body><header><h1>New creative presets ·1.70</h1><p>'+str(count)+'/12 rendered. Four families, three strengths each. New presets have no previous baseline: The six revised Wide Angle and Tilted Miniature presets compare their previous creative renders on the left with their revised renders on the right. Liquid Prism and Vortex compare the unprocessed image with the preset. These are visual iteration references, not previous-release benchmarking baselines. Timing tables show current standalone measurements; previous-iteration timing records are unavailable.</p><p>Approved1.70 engine, Frame Relative, fixed iPhone scene1 at960×455 with the established conversion. Timings measure repeated-frame rendering, not4K playback. All proposals remain unpassed.</p></header><main>'+''.join(cards)+'''</main><script>document.querySelectorAll('.compare').forEach(box=>{const input=box.querySelector('input'),layer=box.querySelector('.before'),line=box.querySelector('.divider');const update=()=>{const v=Number(input.value);layer.style.clipPath=`inset(0 ${100-v}% 0 0)`;line.style.left=v+'%'};input.addEventListener('input',update);update()})</script></body></html>'''
    (WORK/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (WORK/'index.html').write_text(doc)
    destination = Path('/Users/blacktar/Documents/Codex/2026-10-04/continue-the-lens-debaser-project-from/outputs/Lens-Debaser-1.70-New-Creative-Review.html')
    destination.write_text(doc)
    return count

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    manifest = json.loads((PLAN/'manifest.json').read_text())
    assert len(manifest['rows']) == 12
    (WORK/'images').mkdir(parents=True, exist_ok=True)
    if args.prepare_only:
        print('Prepared inventory; completed comparisons:', assemble(manifest))
        return
    if subprocess.run(['pgrep', '-x', 'Resolve'], stdout=subprocess.DEVNULL).returncode == 0:
        raise SystemExit('Quit Resolve before these bounded Metal renders.')
    lock = WORK/'render.lock'
    try:
        lock.mkdir()
    except FileExistsError:
        raise SystemExit('Render lock exists: another run may be active. Check before removing it.')
    try:
        subprocess.run(['make', 'build/ldb-factory-preset-review'], cwd=R, check=True)
        passed = Path((R/'build/integration/1.70/latest-validation-path.txt').read_text().strip())
        library = next(passed.glob('**/LensDebaser.ofx.bundle/Contents/Resources/LDBOptics.metallib'))
        assert sha(library) == 'bcbf6925184a21a4ec152a1bec418b4fe1a5d09a8a2ca7f86930cb81a40379d6', 'Approved engine changed; review context must be updated.'
        engine = WORK/'candidate.metallib'
        if engine.exists():
            assert sha(engine) == sha(library)
        else:
            shutil.copy2(library, engine)
        env = dict(os.environ)
        for key in ('LDB_REVIEW_BASELINE_FIXED','LDB_REVIEW_RENDER_ONLY','LDB_REVIEW_SINGLE_RENDER'):
            env.pop(key, None)
        env.update(LDB_REVIEW_WIDTH='960', LDB_REVIEW_BENCHMARK_FRAMES='4', LDB_REVIEW_BENCHMARK_RUNS='2', LDB_REVIEW_STANDALONE='1')
        dependencies = [R/'build/ldb-factory-preset-review', engine,
                        R/'inputs/redistributable/iphone_milano_dwg_1.tif',
                        R/'inputs/redistributable/Resolve-DWG-Intermediate-to-Rec709-Gamma24-Guide.cube']
        for row in manifest['rows']:
            prefix = WORK/'images'/(row['id']+'--milano1')
            paths = [R/row['candidate']]
            evidence = Path(str(prefix)+'-evidence.json')
            if row.get('frozen_recipe_sha256'):
                assert sha(paths[0]) == row['frozen_recipe_sha256'], 'OK/passed recipe changed: '+row['label']
                validate(prefix)
                assert sha(Path(str(prefix)+'-render.png')) == row['frozen_render_sha256'], 'OK/passed output changed: '+row['label']
                print('Keeping OK/passed output unchanged:', row['label'], flush=True)
                continue
            key = hashlib.sha256(json.dumps([sha(p) for p in dependencies+paths]+[env[k] for k in ('LDB_REVIEW_WIDTH','LDB_REVIEW_BENCHMARK_FRAMES','LDB_REVIEW_BENCHMARK_RUNS')]).encode()).hexdigest()
            if evidence.exists() and json.loads(evidence.read_text())['key'] == key:
                validate(prefix)
                row['status'] = 'Rendered and benchmarked; acceptance pending'
                print('Reusing exact completed case:', row['label'], flush=True)
                continue
            available, method = available_memory()
            print(f'Memory available: {available/1024**3:.2f} GiB ({method}; minimum3GiB).', flush=True)
            if available < 3*1024**3:
                raise SystemExit('Stopped before next case: macOS available-memory estimate below3GiB. Completed cases retained.')
            snapshot = WORK/'inputs'/row['id']
            snapshot.mkdir(parents=True, exist_ok=True)
            print('Reviewing', row['label'], '· iPhone scene1 ·960×455 ·standalone2×4 timed frames', flush=True)
            # Keep the last valid output intact until its replacement passes.
            import tempfile
            with tempfile.TemporaryDirectory(prefix='pending-', dir=WORK) as temp:
                stage = Path(temp)
                recipe = stage/'candidate.ldbpreset'
                shutil.copy2(paths[0], recipe)
                staged_prefix = stage/'output'
                with (snapshot/'render-log.txt').open('w') as log:
                    subprocess.run([str(dependencies[0]),str(engine),str(engine),str(R),str(recipe),str(recipe),'milano1',str(staged_prefix)], cwd=R, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=180, check=True)
                validate(staged_prefix)
                current_image = Path(str(prefix)+'-render.png')
                if current_image.exists():
                    previous = WORK/'previous-iteration'/(row['id']+'--milano1-render.png')
                    previous.parent.mkdir(exist_ok=True)
                    shutil.copy2(current_image, previous)
                    for suffix in ('-metrics.json','-evidence.json'):
                        old = Path(str(prefix)+suffix)
                        if old.exists(): shutil.copy2(old, previous.with_name(row['id']+'--milano1'+suffix))
                    if (snapshot/'candidate.ldbpreset').exists(): shutil.copy2(snapshot/'candidate.ldbpreset', previous.with_suffix('.ldbpreset'))
                    row['visual_previous'] = str(previous.relative_to(R))
                    row['visual_previous_sha256'] = sha(previous)
                    row['visual_previous_context'] = 'Immediate previous rendered state of this preset.'
                for suffix in ('-render.png','-metrics.json'):
                    shutil.copy2(Path(str(staged_prefix)+suffix), Path(str(prefix)+suffix))
                shutil.copy2(recipe, snapshot/'candidate.ldbpreset')
            evidence.write_text(json.dumps({'key':key,'source':'iphone_milano_dwg_1.tif','engine':'Approved1.70 standalone','sizing':'Frame Relative'},indent=2)+'\n')
            row['status'] = 'Rendered and benchmarked; acceptance pending'
            (PLAN/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
        assert assemble(manifest) == 12
        destination = Path('/Users/blacktar/Documents/Codex/2026-10-04/continue-the-lens-debaser-project-from/outputs/Lens-Debaser-1.70-New-Creative-Review.html')
        subprocess.run(['open',str(destination)],check=True)
        print('Complete:12/12 standalone new-preset renders and benchmarks. No install or acceptance.')
    finally:
        lock.rmdir()

def validate(prefix):
    data = json.loads(Path(str(prefix)+'-metrics.json').read_text())
    assert (data['width'],data['height'],data['nonfinite'],data['frames']) == (960,455,0,4)
    assert len(data['runs']) == 2
    import math
    assert all(math.isfinite(run[k]) and run[k]>0 for run in data['runs'] for k in ('gpu','wall'))
    assert data.get('standalone') is True
    assert Path(str(prefix)+'-render.png').is_file()

if __name__ == '__main__':
    main()
