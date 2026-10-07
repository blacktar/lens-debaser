#!/usr/bin/env python3
"""Audit every cinematic recipe and resume bounded family-based Metal reviews."""
from pathlib import Path
import argparse, datetime, hashlib, html, importlib.util, json, os, re, shutil, subprocess

REPO = Path(__file__).resolve().parent.parent
PLAN = REPO / 'presets/experiments/factory-review-1.70-current-library'
CHAT = Path('/Users/blacktar/Documents/Codex/2026-10-04/continue-the-lens-debaser-project-from/outputs')
GROUPS = {
    'prism-anamorphic': {9, 10, 11, 22, 23, 25},
    'pupil-and-drift': {5, 6, 7, 13, 20, 24, 27, 28},
    'geometry-and-field': {14, 16, 18, 19, 21, 26},
    'diffusion-and-colour': {1, 2, 3, 8, 12},
    'capture-and-variation': {4, 15, 17},
}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def save(path, value):
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_text(json.dumps(value, indent=2) + '\n')
    temp.replace(path)

def values(path):
    return {k: float(v) for line in path.read_text().splitlines()
            if '=' in line and not line.lstrip().startswith('#')
            for k, v in [line.split('=', 1)] if k != 'LensDebaserPreset'}

def audit(footage=True):
    manifest = json.loads((PLAN / 'manifest.json').read_text())
    rows = [r for r in manifest['rows'] if '/cinematic-lenses/' in r['candidate']]
    assert len(rows) == 76 and len({r['id'] for r in rows}) == 76
    schema = json.loads((PLAN / 'review-schema.json').read_text())
    spec = importlib.util.spec_from_file_location('preset_validator', REPO / 'scripts/validate-preset.py')
    validator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(validator)
    problems = []
    for row in rows:
        candidate, baseline = REPO / row['candidate'], REPO / row['baseline']
        current, prior = values(candidate), values(baseline)
        errors, warnings = validator.validate(candidate, schema)
        # Explicit dependencies for additions in this revision.
        if current.get('opticalDriftAmount', 0) and current.get('apertureResponse', 0) <= 0:
            errors.append('Optical Drift requires active Aperture Response')
        if current.get('projectionAmount', 0) and current.get('projectionModel', 0) == 0:
            errors.append('Projection Amount requires a projection model')
        if current.get('apertureRimWeight', 0) and current.get('apertureResponse', 0) <= 0:
            errors.append('Rim Weight requires active Aperture Response')
        if current.get('depthMode', 0):
            errors.append('Ordinary cinematic review source has no depth input')
        changed = {k: current.get(k, schema['controls'][k]['default'])
                   for k in current.keys() | prior.keys()
                   if current.get(k, schema['controls'][k]['default']) != prior.get(k, schema['controls'][k]['default'])}
        family = int(row['label'][:2])
        row['review_batch'] = next(k for k, families in GROUPS.items() if family in families)
        row['review_source'] = 'iso' if family in {14,16,18,19,21,25,26} else (
            'hdr' if family in {3,5,6,7,8,9,10,11,12,13,20,22,23,24,27,28} else 'milano1')
        if footage:row['review_source']='milano1'
        row['changes'] = changed
        row['warnings'] = warnings
        row['structural_errors'] = errors
        row['baseline_engine'] = '1.69 shader / shared Frame Relative host scaling'
        row['candidate_engine'] = '1.70 / Frame Relative'
        row['status'] = 'Definition and dependency checks passed; Metal and visual acceptance pending'
        row['rationale'] = row.get('engine_assessment', row['rationale'])
        if changed:
            row['rationale'] += ' Proposed values: ' + ', '.join(f'{k}={v:g}' for k,v in changed.items()) + '.'
        row['rationale'] += (' Inspect straight lines, edge coverage and protected focus region.'
                            if row['review_source'] == 'iso' else
                            ' Inspect bright points, pupil shape, spectral separation and flare/veil.'
                            if row['review_source'] == 'hdr' else
                            ' Inspect texture, colour, contrast and subtle-to-caricature separation.')
        if errors:
            problems.append((row['label'], errors))
    assert not problems, problems
    assert sum(len([r for r in rows if r['review_batch'] == g]) for g in GROUPS) == 76
    return rows

def report(out):
    subprocess.run(['/usr/bin/python3', str(REPO / 'scripts/build-factory-review-report.py'), str(out)], check=True)
    m = json.loads((out / 'manifest.json').read_text())
    done = sum(completed(out,row) for row in m['rows'])
    header = '''<header><h1>All 76 cinematic presets · current-engine review</h1>
<p>Every released cinematic recipe and every current candidate has been inspected. All76 candidates pass the current schema and dependency checks. Revised values remain proposals until visual and benchmark acceptance.</p>
<p>Baseline uses the1.69 shader and original recipe; candidate uses the passed1.70 shader and revised recipe. Both receive the same Frame Relative parameter scaling through the shared render host. The source image,960x455 resolution, conversion and timing procedure are identical. This measures the combined version-and-preset update, not the isolated cost of one control. It is a direct-render test, not separate Resolve captures of the two releases. Legacy authored values are preserved in the baseline.</p>
<p>One targeted source per preset at960px: ISO for geometry/field/prism, existing HDR point-source fixture for bright points, pupil, flare and scatter, or iPhone scene1 for texture and colour. Every strength is included. Two alternating paired runs of four timed frames after four warm-ups per side; timings describe this source and size, not4K playback. Existing passed Effect Size resolution tests remain separate evidence.</p>
<p>Inspect source-dependent effects and family strength progression before agreeing to changes. Native-resolution follow-up or real footage is added only where these comparisons identify uncertainty. Demos are visually reviewed without a benchmark requirement. No new creative families, deployment, factory promotion or release acceptance is implied.</p>'''
    if m.get('review_mode')=='footage':
        header=header.replace('current-engine review','actual-footage review').replace('One targeted source per preset at960px: ISO for geometry/field/prism, existing HDR point-source fixture for bright points, pupil, flare and scatter, or iPhone scene1 for texture and colour.','Every preset uses the same actual iPhone scene1 footage frame at960px, with its original aspect ratio. Charts are separate diagnostic evidence.').replace('Native-resolution follow-up or real footage is added only where these comparisons identify uncertainty.','These are repeated-frame GPU/wall timings on actual scene content, not video decoding, motion tests or4K playback. Separate HDR point-source diagnostics help interpret source-dependent flare and bokeh.')
    counts = ' · '.join(f'{html.escape(g)}: {sum(r["review_batch"]==g for r in m["rows"])}' for g in GROUPS)
    missing=[r for r in m['rows'] if not completed(out,r)]
    if missing:
        families=', '.join(sorted({r['label'][:2] for r in missing}))
        header += f'<p style="color:#ffca80"><strong>INCOMPLETE — not ready for full-library visual acceptance.</strong> Only {done}/76 presets have both renders and valid paired benchmarks. {len(missing)} remain missing (families {families}). The inventory below includes pending definitions, not completed visual results.</p>'
    else:
        header += '<p><strong>Completeness verified: all76 presets have before/after renders and finite paired benchmark results.</strong> Visual and benchmark agreement remains pending.</p>'
    header += f'<p>{done}/76 completed comparisons. {counts}.</p></header>'
    doc = (out/'index.html').read_text()
    start, end = doc.index('<header>'), doc.index('</header>') + len('</header>')
    doc = doc[:start] + header + doc[end:]
    (out/'index.html').write_text(doc)
    CHAT.mkdir(parents=True, exist_ok=True)
    if m.get('review_mode')!='footage':return
    (CHAT/'Lens-Debaser-1.70-Cinematic-Review.html').write_text(
        doc.replace('src="images/', 'src="'+(out/'images').as_uri()+'/'))

def prepare(footage=True):
    rows = audit(footage)
    state = REPO/'build/integration/1.70'
    passed = Path((state/'latest-validation-path.txt').read_text().strip())
    # Use the exact passed normal shader, without rebuilding the engine.
    libraries = list(passed.glob('**/LensDebaser.ofx.bundle/Contents/Resources/LDBOptics.metallib'))
    assert len(libraries) == 1, f'Expected exact passed shader in {passed}'
    candidate = libraries[0]
    baseline = Path((state/'baseline-1.69-path.txt').read_text().strip())/'LensDebaser.ofx.bundle/Contents/Resources/LDBOptics.metallib'
    assert baseline.is_file() and candidate.is_file()
    snapshot_files = [REPO/r[side] for r in rows for side in ('baseline','candidate')]
    snapshot_files += [REPO/'tests/FactoryPresetReview.mm',REPO/'tests/GuideExamples.mm',REPO/'tests/VisualValidation.mm',
                       REPO/'src/engine/LDBOpticsEngine.mm',REPO/'include/LDBOpticsParameters.h',
                       REPO/'include/LDBProjectionCandidateParameters.h',REPO/'include/LDBOpticsEngine.h',
                       REPO/'include/LDBColorReference.h',PLAN/'review-schema.json',REPO/'Makefile',
                       REPO/'scripts/review-all-cinematic-1.70.py',
                       REPO/'inputs/redistributable/ISO_12233-reschart.tif',
                       REPO/'inputs/redistributable/iphone_milano_dwg_1.tif',
                       REPO/'inputs/redistributable/Resolve-DWG-Intermediate-to-Rec709-Gamma24-Guide.cube']
    fingerprint = hashlib.sha256(json.dumps(
        {str(p.relative_to(REPO)):digest(p) for p in snapshot_files},sort_keys=True).encode()
        +digest(baseline).encode()+digest(candidate).encode()+str(footage).encode()).hexdigest()
    latest = state/('latest-cinematic-footage-review-path.txt' if footage else 'latest-all-cinematic-review-path.txt')
    if latest.exists():
        old = Path(latest.read_text().strip())
        if (old/'fingerprint.txt').exists() and (old/'fingerprint.txt').read_text().strip()==fingerprint:
            report(old)
            return old
    out = REPO/'outputs/experiments'/(('cinematic-footage-' if footage else 'cinematic-current-engine-')+datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
    (out/'images').mkdir(parents=True)
    (out/'inputs/baseline').mkdir(parents=True)
    (out/'inputs/candidate').mkdir(parents=True)
    for row in rows:
        for side in ('baseline','candidate'):
            source = REPO/row[side]
            destination = out/'inputs'/side/source.name
            text=source.read_text()
            text='\n'.join(line for line in text.splitlines() if not line.startswith('effectSize='))+'\neffectSize=0\n'
            destination.write_text(text)
            row[side]=str(destination.relative_to(REPO))
        row['evidence_key'] = hashlib.sha256((digest(REPO/row['baseline'])+digest(REPO/row['candidate'])+fingerprint+row['review_source']).encode()).hexdigest()
    shutil.copy2(baseline,out/'baseline.metallib')
    shutil.copy2(candidate,out/'candidate.metallib')
    shutil.copy2(PLAN/'review-schema.json',out/'schema.json')
    m=dict(original_count=76,candidate_count=76,range_revision_count=0,rows=rows,
           review_context='All cinematic families included; Metal/visual approval pending.',fingerprint=fingerprint,review_mode='footage' if footage else 'diagnostic',comparison='version-and-preset-shared-relative')
    if footage:
        reuse_footage(out,m,state)
    save(out/'manifest.json',m)
    (out/'fingerprint.txt').write_text(fingerprint+'\n')
    latest.write_text(str(out)+'\n')
    report(out)
    return out

def reuse_footage(out,m,state):
    previous=state/'latest-cinematic-footage-review-path.txt'
    if not previous.exists():previous=state/'latest-all-cinematic-review-path.txt'
    if not previous.exists():return
    prior=Path(previous.read_text().strip())
    prior_m=json.loads((prior/'manifest.json').read_text())
    if prior_m.get('comparison')!='version-and-preset-shared-relative':return
    if not all(digest(out/name)==digest(prior/name) for name in ('baseline.metallib','candidate.metallib')):return
    lookup={r['id']:r for r in prior_m['rows']}
    reused=0
    renderer=REPO/'build/ldb-factory-preset-review'
    for row in m['rows']:
        old=lookup.get(row['id'])
        if not old or old['review_source']!='milano1' or not completed(prior,old):continue
        if not all(digest(REPO/row[side])==digest(REPO/old[side]) for side in ('baseline','candidate')):continue
        prefix=row['id']+'--milano1'
        evidence=json.loads((prior/'images'/(prefix+'-evidence.json')).read_text())
        if evidence['renderer_sha256']!=digest(renderer):continue
        for suffix in ('-before.png','-after.png','-metrics.json'):
            shutil.copy2(prior/'images'/(prefix+suffix),out/'images'/(prefix+suffix))
        evidence.update(key=row['evidence_key'],reused_from=str(prior))
        save(out/'images'/(prefix+'-evidence.json'),evidence)
        row['status']='Matching actual-footage render and benchmark reused; visual/benchmark agreement pending'
        reused+=1
    print(f'Reused {reused} exact actual-footage comparisons; charts retained separately.')

def completed(out,row):
    prefix = out/'images'/(row['id']+'--'+row['review_source'])
    try:
        data=json.loads(Path(str(prefix)+'-metrics.json').read_text())
        evidence=json.loads(Path(str(prefix)+'-evidence.json').read_text())
        return (data['nonfinite']==0 and data['frames']==4 and len(data['runs'])==2
                and data['width']==960 and data['height']==(455 if row['review_source']=='milano1' else 540) and evidence['key']==row['evidence_key']
                and all(run[k]>0 for run in data['runs'] for k in ('old_gpu','new_gpu','old_wall','new_wall'))
                and all(Path(str(prefix)+suffix).is_file() for suffix in ('-before.png','-after.png')))
    except (OSError,ValueError,KeyError):
        return False

def memory_guard():
    vm=subprocess.check_output(['vm_stat'],text=True)
    match=re.search(r'page size of (\d+) bytes',vm)
    assert match, 'Cannot read memory status'
    counts={k:int(v) for k,v in re.findall(r'^([^:]+):\s+(\d+)\.',vm,re.M)}
    if sum(counts.get(k,0) for k in ('Pages free','Pages inactive','Pages speculative'))*int(match.group(1))<3*1024**3:
        raise SystemExit('Stopped before next case: less than3GiB free/inactive memory. Completed cases are preserved; rerun to resume.')

def run(out,batch):
    if subprocess.run(['pgrep','-x','Resolve'],stdout=subprocess.DEVNULL).returncode==0:
        raise SystemExit('Quit Resolve before these Metal renders.')
    # Only compile the review tool if its source changed; never rebuild metallibs here.
    subprocess.run(['make','build/ldb-factory-preset-review'],cwd=REPO,check=True)
    renderer_hash=digest(REPO/'build/ldb-factory-preset-review')
    m=json.loads((out/'manifest.json').read_text())
    if m.get('comparison')!='version-and-preset-shared-relative' or digest(out/'baseline.metallib')==digest(out/'candidate.metallib'):
        raise SystemExit('Refusing comparison: baseline/candidate must use the distinct1.69 and1.70 libraries with shared Relative scaling.')
    if any(values(REPO/row[side]).get('effectSize')!=0 for row in m['rows'] for side in ('baseline','candidate')):
        raise SystemExit('Refusing comparison: both recipes must explicitly select Frame Relative.')
    if m.get('review_mode')!='footage' or any(row['review_source']!='milano1' for row in m['rows']):
        raise SystemExit('Refusing cinematic speed review: every preset must use the fixed actual-footage source milano1.')
    print('Version comparison: baseline1.69 shader versus candidate1.70 shader; shared Frame Relative host scaling on BOTH sides.',flush=True)
    print('Fixed source: iphone_milano_dwg_1.tif;960x455; identical input pixels for baseline and candidate. No chart sources.',flush=True)
    if batch=='next':
        batch=next((g for g in GROUPS if any(r['review_batch']==g and not completed(out,r) for r in m['rows'])),None)
    if batch is None:
        print('All76 comparisons are complete. Visual and benchmark acceptance remains separate.')
        return
    selected=[r for r in m['rows'] if batch=='all' or r['review_batch']==batch]
    selected.sort(key=lambda r:(list(GROUPS).index(r['review_batch']),r['label']))
    print(f'Batch {batch}: {len(selected)} recipes, one source each,960px, bounded paired timings.',flush=True)
    env=dict(os.environ,LDB_REVIEW_WIDTH='960',LDB_REVIEW_BENCHMARK_FRAMES='4',
             LDB_REVIEW_BENCHMARK_RUNS='2')
    # Ignore unrelated diagnostic flags from earlier CLI sessions.
    for key in ('LDB_REVIEW_RENDER_ONLY','LDB_REVIEW_SINGLE_RENDER','LDB_REVIEW_BASELINE_FIXED'):
        env.pop(key,None)
    try:
        for row in selected:
            if completed(out,row):
                evidence=json.loads((out/'images'/(row['id']+'--'+row['review_source']+'-evidence.json')).read_text())
                if evidence['renderer_sha256']!=renderer_hash:
                    raise SystemExit('Review renderer differs from saved evidence; prepare a fresh review before reusing timings.')
                print('Reusing',row['label'],flush=True)
                continue
            memory_guard()
            prefix=out/'images'/(row['id']+'--'+row['review_source'])
            print('Reviewing',row['label'],row['review_source'],flush=True)
            with (out/(row['id']+'-run.txt')).open('w') as log:
                subprocess.run([str(REPO/'build/ldb-factory-preset-review'),str(out/'baseline.metallib'),
                    str(out/'candidate.metallib'),str(REPO),str(REPO/row['baseline']),str(REPO/row['candidate']),
                    row['review_source'],str(prefix)],cwd=REPO,env=env,stdout=log,stderr=subprocess.STDOUT,
                    timeout=180,check=True)
            data=json.loads(Path(str(prefix)+'-metrics.json').read_text())
            assert data['nonfinite']==0 and data['frames']==4 and len(data['runs'])==2 and (data['width'],data['height'])==(960,455)
            save(Path(str(prefix)+'-evidence.json'),dict(key=row['evidence_key'],renderer_sha256=digest(REPO/'build/ldb-factory-preset-review')))
            row['status']='Finite render and bounded benchmark complete; visual/benchmark agreement pending'
            save(out/'manifest.json',m)
    finally:
        report(out)
    if batch=='all' and not all(completed(out,row) for row in m['rows']):
        raise SystemExit('Full-library review is incomplete. Missing cases must finish before visual acceptance.')
    deliverable=CHAT/'Lens-Debaser-1.70-Cinematic-Review.html'
    subprocess.run(['open',str(deliverable)],check=True)
    print('Review:',deliverable)
    print('Rerun for the next unfinished family batch; completed exact cases are reused.')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--footage',action='store_true',default=True,help='Compatibility option: actual iPhone scene1 is always used for this cinematic review')
    parser.add_argument('--prepare-only',action='store_true')
    parser.add_argument('--batch',choices=['next','all',*GROUPS],default='next')
    args=parser.parse_args()
    # Prevent two invocations from writing the same review concurrently.
    import fcntl
    lock=REPO/'build/integration/1.70/all-cinematic-review.lock'
    lock.parent.mkdir(parents=True,exist_ok=True)
    with lock.open('w') as handle:
        try:fcntl.flock(handle,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:raise SystemExit('A cinematic review is already running.')
        out=prepare(args.footage)
        if args.prepare_only:
            print('All76 cinematic candidates structurally validated. Review:',CHAT/'Lens-Debaser-1.70-Cinematic-Review.html')
        else:run(out,args.batch)

if __name__=='__main__':
    main()
