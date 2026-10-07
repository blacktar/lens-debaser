#!/usr/bin/env python3
"""Assemble saved legacy/current comparisons without rendering either side."""
from pathlib import Path
import hashlib,json,subprocess,html,argparse
R=Path(__file__).resolve().parent.parent
LEGACY=R/'outputs/experiments/cinematic-footage-20261006-182627-391702'
WORK=R/'outputs/experiments/cinematic-review-1.70-working'
DEST=Path('/Users/blacktar/Documents/Codex/2026-10-04/continue-the-lens-debaser-project-from/outputs/Lens-Debaser-1.70-Cinematic-Review.html')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def values(p):
 return {k:float(v) for line in p.read_text().splitlines() if '=' in line and not line.startswith('#') for k,v in [line.split('=',1)] if k not in ('LensDebaserPreset','effectSize')}
def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--batch',default='all');parser.add_argument('--prepare-only',action='store_true');parser.add_argument('--footage',action='store_true');args=parser.parse_args()
 m=json.loads((LEGACY/'manifest.json').read_text());assert len(m['rows'])==76
 active=json.loads((R/'presets/experiments/factory-review-1.70-current-library/manifest.json').read_text());lookup={x['id']:x for x in active['rows']}
 passed=Path((R/'build/integration/1.70/latest-validation-path.txt').read_text().strip());current=next(passed.glob('**/LensDebaser.ofx.bundle/Contents/Resources/LDBOptics.metallib'))
 assert sha(current)==sha(LEGACY/'candidate.metallib'),'Candidate engine changed: new candidate-only results required; do not regenerate legacy.'
 (WORK/'images').mkdir(parents=True,exist_ok=True)
 accepted=(WORK/'acceptance.json').exists()
 for row in m['rows']:
  assert row['review_source']=='milano1'
  assert values(R/row['candidate'])==values(R/lookup[row['id']]['candidate']),row['label']+': changed candidate requires candidate-only rendering; legacy stays frozen.'
  prefix=row['id']+'--milano1';data=json.loads((LEGACY/'images'/(prefix+'-metrics.json')).read_text())
  assert data['nonfinite']==0 and (data['width'],data['height'])==(960,455) and len(data['runs'])==2
  for run in data['runs']:assert all(run[k]>0 for k in ('old_gpu','new_gpu','old_wall','new_wall'))
  evidence=json.loads((LEGACY/'images'/(prefix+'-evidence.json')).read_text());assert evidence['key']==row['evidence_key']
  for suffix in ('-before.png','-after.png','-metrics.json'):
   source=LEGACY/'images'/(prefix+suffix);assert source.is_file();target=WORK/'images'/source.name
   if target.is_symlink():assert target.resolve()==source
   elif target.exists():assert sha(target)==sha(source)
   else:target.symlink_to(source)
  row['baseline_engine']='Legacy1.69 data · unchanged'
  row['candidate_engine']='1.70 · Frame Relative'
  row['status']='PASSED · user visual and benchmark acceptance 2026-10-07' if accepted else 'Saved renders and benchmarks verified; visual/benchmark agreement pending'
 m.update(comparison='stored-legacy-versus-current',baseline_data=str(LEGACY),review_context='Frozen legacy data compared with matching current Relative candidate data.')
 (WORK/'manifest.json').write_text(json.dumps(m,indent=2)+'\n')
 subprocess.run(['/usr/bin/python3',str(R/'scripts/build-factory-review-report.py'),str(WORK)],check=True)
 doc=(WORK/'index.html').read_text();start=doc.index('<header>');end=doc.index('</header>')+len('</header>')
 header='''<header><h1>Cinematic preset review ·1.69 legacy versus1.70 candidate</h1><p><strong>Completeness verified:76/76 presets have baseline/candidate renders and benchmark data on the same iPhone scene1 image at960×455.</strong></p><p>Baseline renders and timings are existing1.69 test records, unchanged. Candidate renders and timings are existing1.70 Frame Relative results, verified against the current preset values and approved engine. No baseline was regenerated or rescaled during assembly.</p><p>The recorded baseline tests used the1.69 shader through the shared render harness with Fixed Pixels; these are stored test results, not independent Resolve captures. The candidate uses Frame Relative. Timings retain their original two alternating runs of four timed frames after four warm-ups; spread indicates variability. They measure repeated-frame rendering at this size, not4K playback or video decoding. This comparison measures the complete version/preset update, not the isolated cost of one feature.</p><p>All results below are real saved outputs. Visual and benchmark agreement remains pending; assembling this working report does not mark a passed archive.</p></header>'''
 if accepted:header=header.replace('Visual and benchmark agreement remains pending; assembling this working report does not mark a passed archive.','PASSED: user approved all76 cinematic presets and their visual/benchmark comparison on2026-10-07. Final release acceptance and packaging are separate.')
 doc=doc[:start]+header+doc[end:]
 notes_path=WORK/'visual-review.json'
 if notes_path.exists():
  notes=json.loads(notes_path.read_text());assert len(notes['families'])==28
  findings='<article id="visual-findings"><h2>Visual inspection · all76 comparisons</h2><p>'+html.escape(notes['scope'])+'</p><p>The common tightening is consistent with the candidate’s Relative footprint at455px height versus the legacy Fixed Pixels reference; these pairs also include recipe changes, so they do not isolate that cause. No broad disappearance of effects is visible. Cropping for14/21 is planned for the next revision.24’s drift need not be conspicuous;26–28 look expected to the user. Benchmark verdicts use absolute milliseconds first, with percentages and run spread as context.17 Medium adds1.97ms GPU and19 Caricature adds0.64ms; the user considers these insignificant here, so percentage-only warnings are withdrawn.</p><table><thead><tr><th>Family · all available strengths inspected</th><th>Finding</th></tr></thead><tbody>'+''.join('<tr><td>'+html.escape(x['family'])+'</td><td>'+html.escape(x['finding'])+'</td></tr>' for x in notes['families'])+'</tbody></table></article>'
  doc=doc.replace('<main>','<main>'+findings,1)
 (WORK/'index.html').write_text(doc)
 references=R/'outputs/experiments/passed/new-creative-1.70-20261007/benchmark-reference-fragment.html'
 if references.exists():doc=doc.replace('</main>',references.read_text()+'</main>',1)
 DEST.write_text(doc.replace('src="images/','src="'+(LEGACY/'images').as_uri()+'/'))
 assert doc.count('class="compare"')==76
 print('Verified and assembled76/76 saved comparisons. No rendering or benchmark regeneration.')
 print('Review:',DEST)
 if not args.prepare_only:subprocess.run(['open',str(DEST)],check=True)
if __name__=='__main__':main()
