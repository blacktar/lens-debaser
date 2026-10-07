#!/usr/bin/env python3
from pathlib import Path
import datetime,json,os,re,shutil,subprocess
repo=Path(__file__).resolve().parent.parent
if subprocess.run(['pgrep','-x','Resolve'],stdout=subprocess.DEVNULL).returncode==0:raise SystemExit('Quit Resolve before this bounded benchmark.')
vm=subprocess.check_output(['vm_stat'],text=True);page=int(re.search(r'page size of (\d+) bytes',vm).group(1));counts={k:int(v) for k,v in re.findall(r'^([^:]+):\s+(\d+)\.',vm,re.M)}
if sum(counts.get(k,0) for k in ('Pages free','Pages inactive','Pages speculative'))*page<3*1024**3:raise SystemExit('Stopped before rendering: less than 3 GiB free/inactive memory.')
state=Path((repo/'build/integration/1.70/latest-frame-relative-candidate-path.txt').read_text().strip());out=repo/'outputs/experiments'/('frame-relative-benchmark-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'));(out/'images').mkdir(parents=True);(out/'inputs').mkdir()
shutil.copy2(state/'LDBOptics.metallib',out/'candidate.metallib');shutil.copy2('/Library/OFX/Plugins/LensDebaser.ofx.bundle/Contents/Resources/LDBOptics.metallib',out/'baseline.metallib')
original=repo/'presets/experiments/cinematic-strength-regression-1.70/baseline/cinematic-lenses/26-Internal-Field-Edge-FX.ldbpreset'
cases=[('fixed-compatibility',1920,original,1),('relative-preset-26-4k',3840,original,0),('relative-glare-1080',1920,repo/'presets/demonstrations/13-Demo-Glare-And-Halo.ldbpreset',0)]
rows=[];compatibility=None
for key,width,recipe,mode in cases:
 old=out/'inputs'/(key+'-old.ldbpreset');new=out/'inputs'/(key+'-new.ldbpreset');old.write_text(recipe.read_text()+'\neffectSize=1\n');new.write_text(recipe.read_text()+f'\neffectSize={mode}\n')
 prefix=out/'images'/(key+'--iso');print('Bounded check:',key,'two alternating runs × four timed frames, per-frame cleanup.',flush=True)
 with (out/(key+'-run.txt')).open('w') as log:
  subprocess.run([str(state/'renderer'),str(out/'baseline.metallib'),str(out/'candidate.metallib'),str(repo),str(old),str(new),'iso',str(prefix)],cwd=repo,env=dict(os.environ,LDB_REVIEW_WIDTH=str(width),LDB_REVIEW_BASELINE_FIXED='1',LDB_REVIEW_BENCHMARK_FRAMES='4',LDB_REVIEW_BENCHMARK_RUNS='2'),stdout=log,stderr=subprocess.STDOUT,timeout=180,check=True)
 d=json.loads(Path(str(prefix)+'-metrics.json').read_text());assert d['nonfinite']==0
 if mode==1:compatibility=d['mae']==0
 rows.append(dict(id=key,label=key,baseline_engine='1.70',decision='compatibility/performance check',rationale='Current installed engine versus candidate on the same source and resolution. '+('Both Fixed Pixels: expect exact output agreement.' if mode else 'Candidate Frame Relative: larger optical footprint is intentional; timings compare complete configurations.'),changes={'effectSize':mode},warnings=[],status='finite; review timings'))
m=dict(original_count=3,candidate_count=3,range_revision_count=0,rows=rows,review_context='Bounded checks: fixed compatibility, 4K aperture, 1080p glare. User already approved relative sizing visually. No automatic acceptance or installation.')
(out/'manifest.json').write_text(json.dumps(m,indent=2));subprocess.run(['/usr/bin/python3',str(repo/'scripts/build-factory-review-report.py'),str(out)],check=True)
p=out/'index.html';doc=p.read_text();a=doc.index('<header>');b=doc.index('</header>',a)+len('</header>');doc=doc[:a]+'<header><h1>Effect Size · bounded compatibility and timing check</h1><p>Three cases only. Two alternating paired runs, four timed frames per side after four warm-ups, with per-frame cleanup and each case in a separate process. Finite components passed. No installation or acceptance.</p><p>Fixed Pixels exact agreement: '+('PASS' if compatibility else 'FAIL')+'</p><p>Relative comparisons change the intended optical footprint. Timing differences measure those configurations, not isolated toggle overhead. Short runs indicate gross regressions; negative differences do not establish speedups.</p></header>'+doc[b:];p.write_text(doc)
# Make image references absolute for the copy in the chat outputs directory.
doc=doc.replace('src="images/','src="'+(out/'images').as_uri()+'/')
report=Path('/Users/blacktar/Documents/Codex/2026-10-04/continue-the-lens-debaser-project-from/outputs/Lens-Debaser-Effect-Size-Benchmarks.html');report.write_text(doc)
(out/'validation.json').write_text(json.dumps({'fixed_exact':compatibility,'nonfinite':0,'accepted':False}))
(repo/'build/integration/1.70/latest-frame-relative-benchmark-path.txt').write_text(str(out)+'\n')
subprocess.run(['open',str(report)],check=True);print('Review:',report)
if not compatibility:raise SystemExit('Fixed Pixels output differs; do not promote.')
