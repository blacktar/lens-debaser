"""Derive documentation illustrations from the shipped control layout."""
import re,json

def update(root, old_groups, descriptions):
 text=(root/'include/LDBControlLayout.h').read_text()
 parse=lambda s:re.findall(r'\{"([^"]*)","([^"]*)","([^"]*)","([^"]*)"\}',s)
 group_rows=parse(text.split('groups[] = {',1)[1].split('};',1)[0]);control_rows=parse(text.split('controls[] = {',1)[1].split('};',1)[0])
 lookup={gid:(label,parent,hint) for gid,label,parent,hint in group_rows}
 schema=json.loads((root/'preset-authoring/Lens-Debaser-Preset-Schema.json').read_text())['controls']
 aliases={'presetGroup':'presets','projectionGroup':'projection','fieldShape':'field-shape','focusField':'focus-field','offAxis':'off-axis','depthGroup':'depth','imageCircle':'image-circle','glareHalo':'glare-halo','highlightResponse':'highlight-response','frontWear':'front-wear','lensDirt':'internal-contamination','output':'blend','anamorphicFlareGroup':'anamorphic-flare'}
 old={g[0]:g for g in old_groups};new=[];roots={}
 for gid,label,parent,hint in group_rows:
  controls=[]
  for cid,group,name,tooltip in control_rows:
   if group!=gid:continue
   spec=schema.get(cid,{})
   if cid=='preset':value,kind='Golden Portrait Prime — Medium','select'
   elif cid in ('loadPreset','savePreset'):value,kind=name,'button'
   elif cid=='workingSpace':value,kind='DaVinci Wide Gamut / Intermediate','select'
   elif cid=='diagnosticView':value,kind='Off','select'
   elif cid in ('opticalCenter','fieldCenter'):value,kind='X 0.500   Y 0.500','point'
   elif cid.endswith('Color'):value,kind='','color'
   elif spec.get('choices'):value,kind=spec['choices'].get(str(int(spec['default'])),str(spec['default'])),'select'
   else:value,kind=str(spec.get('default',0)),'slider'
   controls.append((name,value,kind))
  if not controls:continue
  slug=aliases.get(gid,gid)
  # Root group can contain a direct control alongside its child groups.
  parent_label=lookup[parent][0] if parent else label
  if parent and lookup[parent][1]:parent_label=lookup[lookup[parent][1]][0]+' / '+parent_label
  new.append((slug,parent_label,label,controls));roots[parent_label]=lookup.get(parent,(label,'',hint))[2] or hint
  if slug not in descriptions:descriptions[slug]=(hint or 'Adjust this part of the optical response.', ' '.join(x[3] for x in control_rows if x[1]==gid and x[3]) or hint)
 # Keep nested UI groups inside their owning reference section.
 by_slug={g[0]:g for g in new}; merged=[]
 for gid,label,parent,hint in group_rows:
  slug=aliases.get(gid,gid)
  if slug not in by_slug:continue
  if parent and lookup[parent][1]:continue
  current=by_slug[slug];rows=list(current[3])
  for child_id,child_label,child_parent,child_hint in group_rows:
   if child_parent!=gid:continue
   child=by_slug.get(aliases.get(child_id,child_id))
   if child:
    rows.append((child_label,'','heading'));rows.extend(child[3])
  merged.append((current[0],current[1],current[2],rows))
 new=merged
 roots={g[1]:roots[g[1]] for g in new}
 descriptions['anamorphic-flare']=('Build horizontal highlight streaks, internal reflections and vertical diffraction rays.', 'Flare Amount enables and sets the strength of this group. Flare Threshold selects which scene-linear highlights produce flare; lower thresholds admit more of the image. Flare Color tints the primary flare. Adjust the nested controls below to shape the response. These controls do not change anamorphic geometry or desqueeze footage.')
 descriptions['anamorphic']=('Shape cylindrical geometry independently of flare.', 'Anamorphic Field Aspect changes the field proportions; Cylindrical Distortion bends the image differently across its axes. Anamorphic Fringing adds horizontal color separation in Chromatic Aberration. Horizontal streaks, reflections and diffraction rays are controlled separately under Light & Color → Anamorphic Flare. These controls do not desqueeze footage.')
 descriptions['projection']=('Shape wide-angle perspective and framing.', 'Model selects Off, Equidistant or Stereographic. Amount blends the projection from0–100%. Field Angle is the angle from Optical Center to a frame corner, in degrees:0–89°, half the diagonal field of view; it is independent of Shared Field. Zero Amount or Field Angle preserves the existing mapping. Fill Frame magnifies to fill the frame; Balanced trades magnification against coverage; Preserve Centre Scale retains central size and can stretch source boundaries. Start around55° and adjust Amount before pushing the angle higher.')
 descriptions['processing']=(descriptions['processing'][0],descriptions['processing'][1]+' Effect Size defaults to Frame Relative, keeping pixel-sized blur and scatter proportional to frame dimensions using960×540 as the reference. Fixed Pixels keeps their radius in pixels. This affects blur/scatter size, not normalized geometry, and a preset may store the choice.')
 magnify='When geometry enlarges the image, use4K-or-higher source footage where possible, or enough source detail for the enlargement. A4K timeline does not restore missing source detail. Resampling can soften areas that have no blur or defocus applied; reduce magnification if those areas become soft or smeared.'
 for slug in ('projection','geometry','anamorphic','refractive','prism','field-shape'):
  if slug in descriptions:descriptions[slug]=(descriptions[slug][0],descriptions[slug][1]+' '+magnify)
 return new,roots
