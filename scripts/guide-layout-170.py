"""Derive documentation illustrations from the shipped control layout."""
import re,json

def update(root, old_groups, descriptions):
 text=(root/'include/LDBControlLayout.h').read_text()
 parse=lambda s:re.findall(r'\{"([^"]*)","([^"]*)","([^"]*)","([^"]*)"\}',s)
 group_rows=parse(text.split('groups[] = {',1)[1].split('};',1)[0]);control_rows=parse(text.split('controls[] = {',1)[1].split('};',1)[0])
 lookup={gid:(label,parent,hint) for gid,label,parent,hint in group_rows}
 schema=json.loads((root/'preset-authoring/Lens-Debaser-Preset-Schema.json').read_text())['controls']
 aliases={'finalFraming':'final-framing','presetGroup':'presets','projectionGroup':'projection','fieldShape':'field-shape','focusField':'focus-field','offAxis':'off-axis','depthGroup':'depth','imageCircle':'image-circle','glareHalo':'glare-halo','highlightResponse':'highlight-response','frontWear':'front-wear','lensDirt':'internal-contamination','output':'blend','anamorphicFlareGroup':'anamorphic-flare'}
 old={g[0]:g for g in old_groups};new=[];roots={}
 for gid,label,parent,hint in group_rows:
  controls=[]
  for cid,group,name,tooltip in control_rows:
   if group!=gid:continue
   spec=schema.get(cid,{})
   if cid=='finalFramingMode':value,kind='Off','checkbox'
   elif cid=='finalAutoCropAdjustment':value,kind='0.00','slider-disabled'
   elif cid=='preset':value,kind='Golden Portrait Prime — Medium','select'
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
   if not parent or child_parent!=gid:continue
   child=by_slug.get(aliases.get(child_id,child_id))
   if child:
    rows.append((child_label,'','heading'));rows.extend(child[3])
  merged.append((current[0],current[1],current[2],rows))
 new=merged
 roots={g[1]:roots[g[1]] for g in new}
 roots['Focus & Detail']='Shape edge focus, fine detail, color fringing and bokeh; use a depth map when you need to position focus by subject distance.'
 roots['Light & Color']='Adjust lens color, edge darkening and coverage, then shape glow, glare and flare around highlights.'
 roots['Lens Character']='Add repeatable imperfections, front-element wear and contamination inside the lens.'
 roots['Output']='Adjust the overall mix between the original image and the finished effect.'
 descriptions['anamorphic-flare']=('Build horizontal highlight streaks, internal reflections and vertical diffraction rays.', 'Flare Amount enables and sets the strength of this group. Flare Threshold selects which scene-linear highlights produce flare; lower thresholds admit more of the image. Flare Color tints the primary flare. Adjust the nested controls below to shape the response. These controls do not change anamorphic geometry or desqueeze footage.')
 descriptions['anamorphic']=('Shape cylindrical geometry independently of flare.', 'Anamorphic Field Aspect changes the field proportions; Cylindrical Distortion bends the image differently across its axes. Anamorphic Fringing adds horizontal color separation in Chromatic Aberration. Horizontal streaks, reflections and diffraction rays are controlled separately under Light & Color → Anamorphic Flare. These controls do not desqueeze footage.')
 descriptions['projection']=('Shape wide-angle perspective and framing.', 'Model selects Off, Equidistant or Stereographic. Amount blends the projection from0–100%. Field Angle is the angle from Optical Center to a frame corner, in degrees:0–89°, half the diagonal field of view; it is independent of Shared Field. Zero Amount or Field Angle preserves the existing mapping. Fill Frame magnifies to fill the frame; Balanced trades magnification against coverage; Preserve Centre Scale retains central size and can stretch source boundaries. Start around55° and adjust Amount before pushing the angle higher.')
 descriptions['processing']=(descriptions['processing'][0],descriptions['processing'][1]+' Effect Size defaults to Frame Relative, so blur and scatter keep a similar size relative to the image when output resolution changes. Fixed Pixels keeps their size fixed in pixels, making them proportionally smaller at higher resolutions. This changes effect size, not geometry or overall effect strength, and presets can store the choice.')
 roots['Geometry & Field']='Projection shapes wide-angle perspective; Distortion bends and stretches geometry; Anamorphic Geometry shapes the cylindrical field; Glass Irregularity and Prism Refraction add local displacement and spectral separation. Shared Field positions the spatial response of compatible effects. Optical Center is the shared axis for projection, distortion, vignette, chromatic displacement and flare; Field Center independently positions the response envelope. Each control is explained in the sections below.'
 descriptions['opticsSection']=('Position the optical axis independently of the response field.', 'Optical Center has normalized X and Y coordinates: 0 is the left or top edge, 1 is the right or bottom edge, and 0.5 / 0.5 is the image centre. Moving it relocates the axis used by projection, distortion, vignette, chromatic displacement and flare; it does not simply translate the entire image. Field Center, under Shared Field, independently moves the spatial response envelope. Keep both centred for symmetric treatments, or separate them for decentered character.')
 new=[(slug,root,'Optical Center' if slug=='opticsSection' else title,rows) for slug,root,title,rows in new]
 descriptions['geometry']=('Bend and reshape image geometry around Optical Center.', 'Primary Distortion produces broad barrel or pincushion curvature. Secondary Distortion changes higher-order curvature toward the edges. Moustache Distortion adds wave-shaped radial curvature. Geometry Field Mix progressively confines these conventional distortions to the Shared Field envelope; zero leaves them global and it does not gate Projection. Peripheral Stretch expands or compresses perimeter detail, while Peripheral Warp adds smooth irregular edge deformation. Signed values reverse the direction of each signed distortion control.')
 descriptions['field-shape']=('Position and shape the shared spatial response of enabled lens effects.', 'Field Center positions the response envelope independently of Optical Center. Field Aspect stretches its proportions; Field Rotation (°) turns the envelope. Field Onset sets the protected central region, and Field Transition Width sets how gradually the response grows beyond it. Geometric Swirl rotates image coordinates around Optical Center; its sign reverses the twist, and it is independent of Bokeh Swirl. Shared Field shapes compatible focus, detail, chromatic, prism, pupil and gated geometry responses; it does not set Projection Field Angle or enable those effects by itself.')
 descriptions['refractive']=('Create stable local displacement, magnification and spectral separation from uneven glass.', 'Irregularity Amount sets local displacement and magnification strength. Irregularity Scale sets the size of refractive pockets and waves. Edge Bias moves the response from the full frame toward its perimeter. Directionality stretches the variation along an axis, and Direction turns that axis. Irregular Dispersion separates wavelengths along the local displacement. Irregularity Seed selects another stable pattern; changing the seed does not animate it.')
 descriptions['prism']=('Displace image detail and separate its colors through a directional refractive field.', 'Prism Amount sets displacement strength; Prism Dispersion separates colors along that displacement. Prism Direction chooses the axis, or rotates the local direction in Radial Field mode. Distribution selects Linear Edge, Uniform, Bilateral / Axis, Radial Field or Inverse Field. Linear Edge enters from one side; Uniform covers the frame; Bilateral / Axis is symmetric; Radial Field grows outward; Inverse Field concentrates the response inward. Prism Edge Bias positions the Linear Edge response and Transition Width controls its gradual entry; those two controls apply only to Linear Edge. Bilateral, Radial and Inverse modes use the Shared Field controls.')
 names={'projection':'Projection','geometry':'Primary Distortion, Secondary Distortion, Moustache Distortion, Peripheral Stretch or Peripheral Warp','anamorphic':'Anamorphic Field Aspect or Cylindrical Distortion','refractive':'Irregularity Amount','prism':'Prism Amount','field-shape':'Geometric Swirl'}
 for slug,name in names.items():
  if slug in descriptions:
   note=f'When {name} enlarges the image, use source footage at a higher resolution than the output if possible. Insufficient input detail can slightly blur or defocus the in-focus area. Changing timeline resolution alone will not fix that degradation.'
   descriptions[slug]=(descriptions[slug][0],descriptions[slug][1]+' '+note)
 descriptions['final-framing']=('Crop into the finished image to remove unwanted effects along its edges.', 'Auto Fill Frame estimates the crop needed to hide edges stretched or exposed by lens effects. It is off by default. With Auto Fill on, Adjust Auto starts at 0%; negative values reduce the estimated crop and positive values increase it. With Auto Fill off, Manual Crop starts at 0% and lets you choose the crop yourself. The inactive slider is unavailable; both settings are retained independently when switching modes. Cropping changes composition and enlarges the remaining detail: use higher-resolution source footage when possible. Extreme distortion, large blur or borders already in the source can still need manual fine-tuning. Auto Fill adds rendering work, so leave it off when it is unnecessary.')
 roots['Final Framing']='Finish the framing after the lens effects and overall mix, without applying the optical response again.'
 return new,roots
