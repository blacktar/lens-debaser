#!/usr/bin/env python3
"""Extend the existing audit with per-preset engine/guide assessments; defer new creative work."""
from pathlib import Path
import json,shutil
repo=Path(__file__).resolve().parent.parent
old=repo/'presets/experiments/factory-review-1.70-v1'
root=repo/'presets/experiments/factory-review-1.70-current-library'
if root.exists():raise SystemExit('Current-library review already exists; preserve and inspect it.')
shutil.copytree(old,root)
m=json.loads((root/'manifest.json').read_text());rows=m['rows']
for r in rows:
 for side in ['baseline','candidate']:r[side]=r[side].replace(old.name,root.name)
# Preserve previously authored new creative proposals, outside the active collection.
deferred=[r for r in rows if r['label'].startswith(('29-Balanced-Wide-Street','30-Gentle-Stereo-Documentary'))]
for r in deferred:
 for side in ['baseline','candidate']:
  src=repo/r[side];dst=root/'deferred-new-creative'/side/src.name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.move(src,dst)
m['deferred_new_creative']=[r['label'] for r in deferred];m['rows']=[r for r in rows if r not in deferred]
def values(path):return {k:float(v) for line in path.read_text().splitlines() if '=' in line and not line.startswith('#') for k,v in [line.split('=',1)] if k!='LensDebaserPreset'}
def edit(r,changes,note):
 p=repo/r['candidate'];lines=p.read_text().splitlines();seen=set()
 for i,line in enumerate(lines):
  if '=' in line and not line.startswith('#'):
   key=line.split('=',1)[0]
   if key in changes:lines[i]=f'{key}={changes[key]:g}';seen.add(key)
 lines += [f'{k}={v:g}' for k,v in changes.items() if k not in seen]
 lines.insert(1,'# Current-engine proposal: '+note);p.write_text('\n'.join(lines)+'\n');r['changes'].update(changes);r['decision']='revise existing treatment';r['rationale']+=' '+note
family_notes={
1:'Warm portrait recipe already combines transmission, detail and peripheral focus. Retain geometry; projection would change facial framing without advancing this intent.',
2:'The silver/diffusion identity comes from reduced microcontrast, cool transmission and halo. Retain the different tier balances rather than add wide-angle geometry.',
3:'Wear, coating loss and threshold-driven scatter already implement the uncoated character. Preserve highlight/black-level balance; no projection or extra wear is needed.',
4:'Fixed distortion, variation and glass irregularity represent zoom character, but the recipe does not animate focus breathing. Correct the description rather than imply time-varying lens simulation.',
5:'Tangential pupil shaping and field curvature already establish rotating bokeh. Do not substitute Optical Drift for Bokeh Swirl: they move different parts of the footprint.',
6:'Oval polygon pupil, displaced field, swirl and curvature already work together for Petzval character. Preserve the intentional oval orientation and existing tier separation.',
7:'Circular low-softness pupil and Rim Weight establish bubble bokeh. The Subtle recipe currently omits Rim Weight; give that tier a restrained rim contribution.',
8:'Bloom, independent glare, halo and transmission shoulder already provide pearlescent diffusion. Keep geometry neutral and assess bright-source contrast rather than add projection.',
9:'Blue flare, oval pupil and anamorphic chromatic spread already express scope character. Preserve authored pupil orientation; audit the Caricature flare range separately.',
10:'Warm streak color, amber transmission and oval pupil already distinguish the compact scope. Keep framing unchanged; preserve the warm-versus-blue distinction.',
11:'Cylindrical geometry, peripheral warp and directional irregularity already produce bent scope edges. Adding radial projection would stack unrelated geometry and risk unusable borders.',
12:'Highlight-driven blue flare, glare and bloom are the identity. Retain distinct thresholds and inspect night/practical highlights; daylight-only comparisons are insufficient.',
13:'Cat-Eye, clip/shift and coma already exploit the current pupil engine. Judge outer point highlights; drift would introduce a second asymmetric trait not needed here.',
14:'This is the existing wide-angle family most suited to the new projection model. Try Equidistant with increasing tier amounts; reduce overlapping polynomial/peripheral geometry rather than stacking everything.',
15:'Displaced field and stable variation/irregularity already represent imperfect rehousing. Pupil variation is dormant where Aperture Response is zero; remove the unused setting, do not add blur solely to activate it.',
16:'Image-circle pressure, coma, color fringing and green transmission establish small-format CCTV character. Retain coverage shape; projection would compound existing distortion and cropping.',
17:'Capture settings actually scale enabled near-focus, pupil and chromatic responses. Preserve the direct-effects/context relationship; this is not a depth-map or projection demonstration.',
18:'Elliptical rotated field and asymmetric blur/color create the objective character. Retain field geometry; normalize oversized seeds and verify repeatable patterns in Resolve.',
19:'Strong displaced/rotated field plus directional smear already expresses freelens asymmetry. Keep drift out to avoid replacing the field-focus signature with translated bokeh.',
20:'Unconventional polygon pupil, rim/shift, wear and irregularity already express adapted projector glass. Optical projection is a different concept; do not add it because of the family name.',
21:'The bodycam signature is an appropriate existing wide-field candidate. Try a restrained Equidistant contribution while reducing overlapping moustache distortion; retain its stressed peripheral optics.',
22:'Reference-inspired Hawk flare layers, reflection paths and pupil aspect already use the advanced engine. Preserve the authored orientation and reference rationale; do not add radial projection or generic drift.',
23:'Reference-inspired Cooke thin flare/rays and reflection geometry are deliberately authored. Preserve their identity; thickness below 0.1 is already clamped in the engine, so normalization should preserve the implemented streak width.',
24:'The displaced field, clipping and pupil shift make this a plausible beneficiary of Directed Optical Drift. Add a restrained directional drift across tiers while retaining the shaped pupil and existing sharp-source geometry.',
25:'One-sided Prism Distribution is intentionally the default Linear Edge. Keep the directional edge treatment rather than change to Radial merely because it is newer.',
26:'Previously passed compound aperture/field treatment remains valid. Remove only dormant Prism Distribution; do not activate an unrelated prism effect.',
27:'This 1.69 signature already uses Directed Optical Drift with restrained aperture response and chromatic field. Keep its tested role distinct from the stronger radial signature.',
28:'This 1.69 signature already combines Radial Optical Drift with opposing focus colors. Retain as the stronger spectral example; do not add projection to make every new feature active.'}
demo_notes={
1:'Capture modifies already enabled field, focus/color and vignette effects. Keep dependencies; document Capture Context separately from projection angle.',
2:'Look macros remain a coordinated treatment. Keep the visible contributions and clarify macro processing precedes individual optical controls.',
3:'Gated polynomial geometry remains a useful Distortion demo independent of Projection. Normalize transition width; preserve the displaced optical axis.',
4:'The field-shape demo currently demonstrates aspect/center/rotation and downstream focus/color but not Geometric Swirl. Add restrained swirl so the shared-field rotation of image structure is represented.',
5:'Field focus and directional smear demonstrate the current continuous blur response. Preserve values until native-resolution review; preview scaling must not be mistaken for engine softness.',
6:'Directional detail controls remain meaningful after field focus. Keep; judge fine texture at native resolution before retuning contrast/detail amounts.',
7:'Lateral and longitudinal color are enabled with independent chromatic transitions. Keep; use high-contrast edges and defocused detail, not uniform surfaces.',
8:'The existing Anamorphic demo mixes geometry, chromatic spread and flare. Revise to isolate Anamorphic Geometry now that flare and fringing have separate UI homes; Demo 27 already demonstrates flare.',
9:'Polygon pupil, Cat-Eye and bokeh swirl already expose the aperture reconstruction engine. Retain enabled response and distinguish footprint shaping from sharp-image Geometric Swirl.',
10:'All three vignette types are deliberately enabled. Keep coverage dependencies visible when loaded; optical illumination falloff is not projection framing.',
11:'Mechanical Vignette correctly enables image-circle controls. Retain; no auto-crop feature exists yet.',
12:'Bloom uses its own threshold/radius and moderate horizontal stretch. Keep; point highlights reveal energy spread more clearly than diffuse daylight.',
13:'Independent glare threshold and halo are correctly enabled. Keep warm scatter isolated from direct transmission color.',
14:'Direct transmission color/density/contrast/shoulder are enabled. Keep; this is not scatter extraction and must not be described as global highlight knee.',
15:'Existing bloom/glare/halo/coma dependencies make shared knee visible. Rename description to Scatter Threshold Softness and state it affects extraction, not final-image tone.',
16:'Coma is enabled with its own threshold; halo is a supporting contribution. Keep, inspect isolated off-axis points.',
17:'Compatible field, pupil, chromatic and transmission effects are all enabled for variation. Keep stable seed and explain it is repeatable, not animated noise.',
18:'The recipe correctly selects Near Black (depthMode=2). Clarify the dedicated Depth Map connector and retain interpretation; use a real map for host validation.',
20:'Wear controls all have active direct/scatter contributions. Keep distinct from internal contamination; judge highlights and ordinary detail.',
21:'Glass Irregularity already has amount, anisotropy and dispersion enabled. Keep deterministic seed; do not confuse local glass deformation with ideal projection.',
22:'Peripheral Stretch remains distinct from projection magnification. Normalize transition width; keep polynomial and projection neutral to isolate its role.',
23:'Peripheral Warp remains distinct from ideal projection. Normalize transition width and retain its gradual edge response.',
24:'Internal contamination uses cloud density plus illumination-driven scatter. Keep; no additional geometry is needed.',
25:'Previously accepted tangential pupil swirl is intentionally strong. Preserve its approved role; Geometric Swirl needs a separate image-structure demonstration.',
26:'Curved field focus and off-axis pupil shaping already complement each other. Keep; no projection is needed to explain the Petzval-like field.',
27:'Structured flare already enables streak layers and reflection paths. Keep; revised group names must be reflected in guide text, not a new duplicate preset.',
28:'Flare Amount correctly enables diffraction rays; glare supports visibility. Keep and preserve the dependency after UI regrouping.',
29:'Enabled pupil shift/clipping with modest radius isolates asymmetric edge closure. Keep rather than stack Directed Drift into this dedicated demo.',
30:'Rim Weight is enabled over a filled pupil. Keep; verify it remains distinct from the ordinary aperture demo.',
31:'Radial Prism follows Shared Field and intentionally ignores Linear Edge bias/softness. Keep; distribution choices are already documented.',
32:'Optical Drift was added and documented in 1.69 with enabled aperture dependency. Keep Radial demo; new tangential/directed demos are not required to document an already explained control.'}
guide=(repo/'scripts/build-user-guide.py').read_text();assert '"projection"' not in guide and 'Optical Drift' in guide
for r in m['rows'][:107]:
 p=repo/r['baseline'];f=values(p);n=int(r['label'][:2]);demo='demonstrations/' in r['baseline'];note=(demo_notes if demo else family_notes)[n]
 r['engine_assessment']=note;r['rationale']=note+(' Proposed range corrections: '+', '.join(r['changes'])+'.' if r['changes'] else '')
 r['authored_values']=f;r['guide_coverage']='Existing feature documented; UI names/group locations need update.'
 r['status']='definition/engine review complete; proposed changes await evidence and agreement'
 if not demo and n==14:
  tier=int(r['label'].split('-')[-2]);edit(r,{'projectionModel':1,'projectionAmount':{1:20,2:45,3:70}[tier],'projectionFieldAngle':55,'projectionFraming':1,'distortionK1':{1:-.006,2:-.009,3:-.014}[tier],'distortionK2':{1:.025,2:.045,3:.08}[tier],'moustacheK3':{1:.035,2:.07,3:.12}[tier],'peripheralStretch':{1:.04,2:.08,3:.14}[tier],'peripheralWarp':{1:.03,2:.06,3:.12}[tier]},'Keep the existing wide-family identity while assigning most large-scale mapping to Projection; compare composition and usable edges.')
 if not demo and n==21:edit(r,{'projectionModel':1,'projectionAmount':20,'projectionFieldAngle':55,'projectionFraming':1,'distortionK1':-.006,'distortionK2':.025,'moustacheK3':.03},'Retain the bodycam signature but avoid doubling its polynomial bend with the new mapping.')
 if not demo and n==24:
  tier=int(r['label'].split('-')[-2]);edit(r,{'opticalDriftMode':2,'opticalDriftAngle':-18,'opticalDriftAmount':{1:.06,2:.12,3:.22}[tier]},'Directed pupil-footprint drift supports decentered character without moving sharp source geometry.')
 if not demo and n==7 and 'Subtle' in r['label']:edit(r,{'apertureRimWeight':.12},'Give the subtle bubble-bokeh tier its missing restrained rim contribution.')
 if not demo and n==15 and f.get('variationPupilIrregularity',0)>0 and f.get('apertureResponse',0)==0:edit(r,{'variationPupilIrregularity':0},'Remove dormant pupil variation without enabling new blur.')
 if demo and n==4:edit(r,{'swirl':.18},'Demonstrate Geometric Swirl in the existing Shared Field demo; keep it distinct from pupil swirl.')
 if demo and n==8:edit(r,{'anamorphicFlareAmount':0,'anamorphicAberration':0},'Isolate geometry; existing Chromatic and Structured Flare demos retain the other behaviors.')
 if demo and n in [15,18] or (not demo and n==4):
  cp=repo/r['candidate'];lines=cp.read_text().splitlines();comments={'15':'Shared Scatter Threshold Softness changes enabled highlight extraction, not final-image highlight compression.','18':'Connect a depth map to the dedicated Depth Map input; this preset selects Near Black interpretation (depthMode=2).','04':'Static documentary zoom-inspired optical character; no automatic animated focus breathing is modeled.'}
  lines=[('# '+comments[f'{n:02d}']) if i==3 and line.startswith('#') else line for i,line in enumerate(lines)];cp.write_text('\n'.join(lines)+'\n');r['decision']='revise description' if not r['changes'] else r['decision'];r['description_update']=comments[f'{n:02d}']
for r in m['rows'][107:]:r['guide_coverage']='Projection is absent from the current guide; new demo required.'
m['candidate_count']=113;m['notes']+=['Scope: review every existing preset, then add demos of undocumented new features. New creative families are deferred.','Range correction alone is not a full creative/engine review. Family and per-file assessments are now included.']
m['guide_audit']={'undocumented_new_controls':['projectionModel','projectionAmount','projectionFieldAngle','projectionFraming'],'already_documented':['Optical Drift and modes','Prism Distribution','Expanded aperture range','Continuous field/aperture transitions'],'ui_updates':['Six sections and revised hierarchy','Anamorphic geometry / fringing / flare split','Shared Field versus Projection Field Angle','Scatter Threshold Softness name/meaning','Input & Diagnostics, Capture Context, Output labels']}
# Selection comes after review; no representative-only substitute for the 107-file audit.
m['batches']={'demos':[r['id'] for r in m['rows'][107:]],'changed-existing':[r['id'] for r in m['rows'][:107] if r['changes'] or r.get('description_update')],'all-current':[r['id'] for r in m['rows'][:107]]}
(root/'manifest.json').write_text(json.dumps(m,indent=2)+'\n')
print('Completed engine/intent review: 31 existing demos + 76 cinematic presets. Six undocumented-feature demos retained. Two new creative proposals deferred.')
