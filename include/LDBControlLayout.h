#pragma once
// Candidate presentation only. IDs, values and DSP remain unchanged.
#include <string>
#include <set>
#include <vector>
#include <stdexcept>
namespace LDBControlLayout {
struct Group {const char *id,*label,*parent,*hint;};
struct Control {const char *id,*group,*label,*hint;};
inline constexpr Group groups[] = {
  {"setupSection","Setup","","Presets, input encoding and broad creative context."},
  {"presetGroup","Presets","setupSection","Load and save complete lens treatments."},
  {"processing","Input & Diagnostics","setupSection","Match the input encoding and inspect the effect."},
  {"capture","Capture Context","setupSection","Context scales existing optical responses; it is not a projection or camera reconstruction."},
  {"look","Look Macros","setupSection","Coordinated creative contributions applied before individual optical controls."},
  {"opticsSection","Geometry & Field","","Projection and coordinate mapping, followed by the shared spatial response controls."},
  {"projectionGroup","Projection","opticsSection","Ideal wide-angle mapping before distortion. Amount blends geometry; Field Angle is half-diagonal."},
  {"geometry","Distortion","opticsSection","Conventional and peripheral distortion around the shared Optical Center."},
  {"anamorphic","Anamorphic Geometry","opticsSection","Anamorphic field and cylindrical distortion; this does not desqueeze footage."},
  {"refractive","Glass Irregularity","opticsSection","Local displacement and wavelength-dependent separation from uneven glass."},
  {"prism","Prism Refraction","opticsSection","Directional refractive displacement and dispersion."},
  {"fieldShape","Shared Field","opticsSection","Independent response field for focus, detail, pupil and gated geometry; this does not set projection field angle."},
  {"pupilSection","Focus & Detail","","Field focus, frequency response, chromatic effects, aperture footprint and optional depth."},
  {"focusField","Field Focus & Smear","pupilSection","Off-axis focus loss and directional spread."},
  {"detail","Detail Transfer","pupilSection","Texture and fine-detail transfer, respecting the existing focus response."},
  {"chromatic","Chromatic Aberration","pupilSection","Radial, anamorphic and near/far chromatic separation."},
  {"offAxis","Coma","pupilSection","Signed asymmetric highlight tails."},
  {"aperture","Aperture & Bokeh","pupilSection","Pupil reconstruction and optical drift; Aperture Amount enables this stage."},
  {"depthGroup","Depth & Focus","pupilSection","Optional input depth and focus-plane response for aperture and optical scatter."},
  {"lightSection","Light & Color","","Direct transmission and coverage plus reconstructed highlight scatter."},
  {"transmission","Transmission","lightSection","Direct lens throughput and tone before scatter extraction."},
  {"vignette","Vignette","lightSection","Illumination falloff around Optical Center."},
  {"imageCircle","Image Circle","lightSection","Boundary for Mechanical Vignette; this is separate from projection framing."},
  {"bloom","Bloom","lightSection","Highlight bloom extraction and spread."},
  {"glareHalo","Glare & Halo","lightSection","Veiling glare and spherical-aberration halo."},
  {"anamorphicFlareGroup","Anamorphic Flare","lightSection","Enable horizontal flare, then adjust streaks, reflections and rays."},
  {"flareStreaks","Streak Shape","anamorphicFlareGroup","Primary, layered and secondary streak structure."},
  {"flareGhosts","Reflections","anamorphicFlareGroup","Filled reflection paths from coherent sources."},
  {"flareRays","Diffraction Rays","anamorphicFlareGroup","Vertical rays reconstructed around coherent sources."},
  {"highlightResponse","Scatter Threshold Softness","lightSection","Shared soft knee for highlight extraction; does not compress the final image."},
  {"advancedSection","Lens Character","","Stable instance variation, front wear and internal contamination modulate several processing stages."},
  {"variation","Lens Variation","advancedSection","Repeatable variation of active optical responses."},
  {"frontWear","Front Element Wear","advancedSection","Direct attenuation and illumination-driven scatter from wear."},
  {"lensDirt","Internal Contamination","advancedSection","Direct density clouds and scatter from internal deposits."},
  {"output","Output","","Final original/effect blend after the optical graph."},
#if defined(LDB_FINAL_FRAMING_EXPERIMENT) || defined(LDB_ENABLE_FINAL_FRAMING)
  {"finalFraming","Final Framing","","Crop the finished optical result without changing its lens response."},
#endif
};
inline constexpr Control controls[] = {
#if defined(LDB_FINAL_FRAMING_EXPERIMENT) || defined(LDB_ENABLE_FINAL_FRAMING)
  {"finalFramingMode","finalFraming","Auto Fill Frame",""},
  {"finalAutoCropAdjustment","finalFraming","Adjust Auto",""},
  {"finalManualCrop","finalFraming","Manual Crop (%)",""},
#endif
  {"preset","presetGroup","Preset",""},
  {"loadPreset","presetGroup","Load",""},
  {"savePreset","presetGroup","Save",""},
  #if defined(LDB_RESOLUTION_RELATIVE_CANDIDATE) || defined(LDB_ENABLE_FRAME_RELATIVE)
  {"effectSize","processing","Effect Size",""},
#endif
  {"workingSpace","processing","Input Color Space",""},
  {"diagnosticView","processing","Diagnostic View",""},
  {"captureInfluence","capture","Capture Influence",""},
  {"captureGate","capture","Gate / Capture Format",""},
  {"captureFocalLength","capture","Focal Length (mm)",""},
  {"captureAperture","capture","Aperture (f-number)",""},
  {"captureFocusDistance","capture","Focus Distance (cm)",""},
  {"lookInfluence","look","Look Amount","Overall amount of the coordinated Look macro contributions. Zero removes those contributions."},
  {"lookCharacter","look","Character",""},
  {"lookVintageBias","look","Vintage Bias",""},
  {"lookVintageCaricatureBias","look","Vintage Caricature",""},
  {"lookExoticBias","look","Exotic Bias",""},
  {"lookAnamorphicBias","look","Classic 2x Anamorphic Bias",""},
  {"projectionModel","projectionGroup","Model",""},
  {"projectionAmount","projectionGroup","Amount (%)",""},
  {"projectionFieldAngle","projectionGroup","Field Angle (half-diagonal °)","Angle from the optical axis to a frame corner, in degrees (half the diagonal field of view). Zero disables projection. Near 89° some framings magnify heavily. Independent of Shared Field controls."},
  {"projectionFraming","projectionGroup","Framing","Fill Frame magnifies to keep the frame filled; Balanced trades magnification against edge coverage; Preserve Centre Scale maintains central scale and may stretch source boundaries."},
  {"opticalCenter","opticsSection","Optical Center","Shared center for projection, distortion, vignette, chromatic displacement and flare. Field Center independently shapes spatial optical responses."},
  {"distortionK1","geometry","Primary Distortion",""},
  {"distortionK2","geometry","Secondary Distortion",""},
  {"moustacheK3","geometry","Moustache Distortion",""},
  {"geometryFieldAmount","geometry","Geometry Field Mix","Blends conventional distortion into the Shared Field envelope. Zero leaves distortion global. Does not gate projection."},
  {"peripheralStretch","geometry","Peripheral Stretch",""},
  {"peripheralWarp","geometry","Peripheral Warp",""},
  {"anamorphicSqueeze","anamorphic","Anamorphic Field Aspect",""},
  {"anamorphicDistortion","anamorphic","Cylindrical Distortion",""},
  {"refractiveIrregularity","refractive","Irregularity Amount",""},
  {"refractiveScale","refractive","Irregularity Scale",""},
  {"refractiveEdgeBias","refractive","Edge Bias",""},
  {"refractiveAnisotropy","refractive","Directionality",""},
  {"refractiveRotation","refractive","Direction",""},
  {"refractiveDispersion","refractive","Irregular Dispersion",""},
  {"refractiveSeed","refractive","Irregularity Seed",""},
  {"prismAmount","prism","Prism Amount",""},
  {"prismDirection","prism","Prism Direction",""},
  {"prismDispersion","prism","Prism Dispersion",""},
  {"prismEdgeBias","prism","Prism Edge Bias",""},
  {"prismSoftness","prism","Transition Width",""},
  {"prismDistribution","prism","Distribution",""},
  {"fieldCenter","fieldShape","Field Center",""},
  {"fieldAspect","fieldShape","Field Aspect",""},
  {"fieldRotation","fieldShape","Field Rotation (°)",""},
  {"responseFieldOnset","fieldShape","Field Onset",""},
  {"responseFieldFalloff","fieldShape","Field Transition Width",""},
  {"swirl","fieldShape","Geometric Swirl","Rotates image coordinates around Optical Center; independent of Bokeh Swirl."},
  {"cornerSharpnessLoss","focusField","Edge Focus Loss",""},
  {"astigmatism","focusField","Astigmatism",""},
  {"fieldCurvature","focusField","Field Curvature",""},
  {"radialSmear","focusField","Radial Smear",""},
  {"tangentialSmear","focusField","Tangential Smear",""},
  {"microContrast","detail","Microcontrast",""},
  {"fineDetail","detail","Fine Detail",""},
  {"detailEdgeFalloff","detail","Edge Detail Loss",""},
  {"sagittalDetail","detail","Sagittal Detail",""},
  {"tangentialDetail","detail","Tangential Detail",""},
  {"detailScale","detail","Detail Scale",""},
  {"lateralCARed","chromatic","Red Fringing",""},
  {"lateralCABlue","chromatic","Blue Fringing",""},
  {"chromaticFieldOnset","chromatic","Chromatic Onset",""},
  {"chromaticFieldFalloff","chromatic","Chromatic Transition Width",""},
  {"longitudinalCA","chromatic","Longitudinal Amount",""},
  {"longitudinalCARadius","chromatic","Longitudinal Radius (px)",""},
  {"anamorphicAberration","chromatic","Anamorphic Fringing",""},
  {"nearFocusColor","chromatic","Near-Focus Color",""},
  {"farFocusColor","chromatic","Far-Focus Color",""},
  {"coma","offAxis","Coma",""},
  {"comaThreshold","offAxis","Coma Threshold",""},
  {"apertureResponse","aperture","Aperture Amount",""},
  {"apertureShape","aperture","Aperture Shape",""},
  {"apertureRadius","aperture","Aperture Radius (px)",""},
  {"apertureBladeCount","aperture","Blade Count",""},
  {"apertureBladeCurvature","aperture","Blade Curvature",""},
  {"apertureRotation","aperture","Aperture Rotation (°)",""},
  {"apertureSoftness","aperture","Edge Softness",""},
  {"apertureAspect","aperture","Pupil Aspect",""},
  {"apertureCatEye","aperture","Cat-Eye",""},
  {"apertureBokehSwirl","aperture","Bokeh Swirl",""},
  {"aperturePupilShift","aperture","Pupil Shift",""},
  {"aperturePupilClip","aperture","Pupil Clipping",""},
  {"apertureRimWeight","aperture","Pupil Rim Weight",""},
  {"opticalDriftAmount","aperture","Drift Amount",""},
  {"opticalDriftMode","aperture","Drift Direction",""},
  {"opticalDriftAngle","aperture","Drift Angle (°)",""},
  {"depthMode","depthGroup","Depth Interpretation",""},
  {"depthNear","depthGroup","Input Near",""},
  {"depthFar","depthGroup","Input Far",""},
  {"depthFocus","depthGroup","Focus Depth",""},
  {"responseDefocusOnset","depthGroup","Defocus Onset",""},
  {"responseDefocusFalloff","depthGroup","Full Defocus Distance","Normalized depth distance from Focus Depth at which defocus reaches full strength. This is an endpoint, not a transition width."},
  {"responseScatterEdgeProtection","depthGroup","Depth Edge Protection",""},
  {"depthEdgeSoftness","depthGroup","Depth Edge Softness",""},
  {"transmissionColorAmount","transmission","Color Amount",""},
  {"transmissionDensity","transmission","Density (stops)",""},
  {"transmissionContrast","transmission","Transmission Contrast",""},
  {"transmissionHighlightSoftness","transmission","Highlight Softness",""},
  {"transmissionColor","transmission","Transmission Color",""},
  {"vignetteNatural","vignette","Natural Vignette",""},
  {"vignetteOptical","vignette","Optical Vignette",""},
  {"vignetteMechanical","vignette","Mechanical Vignette",""},
  {"imageCircleSize","imageCircle","Image Circle Size",""},
  {"imageCircleAspect","imageCircle","Image Circle Aspect",""},
  {"imageCircleSoftness","imageCircle","Image Circle Softness",""},
  {"bloomEnergy","bloom","Bloom Amount",""},
  {"bloomThreshold","bloom","Bloom Threshold",""},
  {"bloomRadius","bloom","Bloom Radius",""},
  {"bloomHorizontalStretch","bloom","Bloom Stretch",""},
  {"sphericalHalo","glareHalo","Spherical Halo",""},
  {"glareEnergy","glareHalo","Glare Amount",""},
  {"glareThreshold","glareHalo","Glare Threshold",""},
  {"glareRadius","glareHalo","Glare Radius",""},
  {"glareColorAmount","glareHalo","Glare Color Amount",""},
  {"glareColor","glareHalo","Glare Color",""},
  {"anamorphicFlareAmount","anamorphicFlareGroup","Flare Amount",""},
  {"anamorphicFlareThreshold","anamorphicFlareGroup","Flare Threshold",""},
  {"anamorphicFlareColor","anamorphicFlareGroup","Flare Color",""},
  {"anamorphicFlareRadius","flareStreaks","Flare Radius",""},
  {"anamorphicFlareThickness","flareStreaks","Flare Thickness",""},
  {"anamorphicFlareCoreAmount","flareStreaks","Flare Core",""},
  {"anamorphicFlareAsymmetry","flareStreaks","Flare Asymmetry",""},
  {"anamorphicFlareBandAmount","flareStreaks","Flare Bands",""},
  {"anamorphicFlareBandSeparation","flareStreaks","Band Separation",""},
  {"anamorphicFlareSecondaryAmount","flareStreaks","Secondary Streak",""},
  {"anamorphicFlareSecondaryOffset","flareStreaks","Secondary Offset",""},
  {"anamorphicFlareGhostAmount","flareGhosts","Reflection Amount",""},
  {"anamorphicFlareGhostPosition","flareGhosts","Reflection Position",""},
  {"anamorphicFlareGhostScale","flareGhosts","Reflection Scale",""},
  {"anamorphicFlareGhostCount","flareGhosts","Reflection Paths",""},
  {"anamorphicFlareGhostSpacing","flareGhosts","Reflection Spacing (px)",""},
  {"anamorphicFlareGhostScaleDecay","flareGhosts","Reflection Size Decay",""},
  {"anamorphicFlareGhostEnergyDecay","flareGhosts","Reflection Energy Decay",""},
  {"anamorphicFlareGhostColor","flareGhosts","Reflection Color",""},
  {"diffractionRayAmount","flareRays","Vertical Rays",""},
  {"diffractionRayLength","flareRays","Ray Length",""},
  {"responseHighlightKnee","highlightResponse","Threshold Softness","Softens extraction around the thresholds of active bloom, glare, halo, coma and flare. Does not soften final-image highlight tone."},
  {"variationAmount","variation","Variation Amount",""},
  {"variationSeed","variation","Variation Seed",""},
  {"variationFieldAsymmetry","variation","Field Asymmetry",""},
  {"variationPupilIrregularity","variation","Pupil Irregularity",""},
  {"variationChromaticAsymmetry","variation","Chromatic Asymmetry",""},
  {"variationTransmissionUnevenness","variation","Transmission Unevenness",""},
  {"frontHaze","frontWear","Cleaning Haze",""},
  {"cleaningMarks","frontWear","Cleaning Marks",""},
  {"scratchAmount","frontWear","Deep Scratches",""},
  {"scratchDirection","frontWear","Scratch Direction",""},
  {"damageScale","frontWear","Mark Scale",""},
  {"coatingWear","frontWear","Coating Wear",""},
  {"coatingWearScale","frontWear","Wear Patch Scale",""},
  {"damageSeed","frontWear","Damage Seed",""},
  {"internalDirtAmount","lensDirt","Internal Dirt Amount",""},
  {"internalDirtScale","lensDirt","Internal Dirt Size",""},
  {"internalDirtSmear","lensDirt","Internal Smear",""},
  {"internalDirtScatter","lensDirt","Internal Scatter",""},
  {"internalDirtSoftness","lensDirt","Cloud Softness",""},
  {"internalDirtComplexity","lensDirt","Cloud Complexity",""},
  {"internalDirtSeed","lensDirt","Internal Dirt Seed",""},
  {"effectBlend","output","Effect Blend",""},
};
inline const Group* findGroup(const std::string& id) {
 for(const auto& g:groups)if(id==g.id)return &g;
 return nullptr;
}
inline const Control* findControl(const std::string& id) {
 for(const auto& c:controls)if(id==c.id)return &c;
 return nullptr;
}
// These access groups must be visible before any preset has been applied.
inline bool initiallyOpen(const std::string& id) {
 return id=="setupSection" || id=="presetGroup" || id=="processing" || id=="output";
}
inline std::set<std::string> expandedGroups(const std::vector<std::string>& configured) {
 std::set<std::string> result;
 for(const auto& g:groups)if(initiallyOpen(g.id))result.insert(g.id);
 auto open=[&](std::string id) {
  for(int limit=0;!id.empty();++limit) {
   if(limit>8)throw std::logic_error("Control group cycle");
   const auto* g=findGroup(id);
   if(!g)throw std::logic_error("Unknown control group");
   result.insert(id);id=g->parent;
  }
 };
 for(const auto& id:configured) {
  const auto* c=findControl(id);
  if(!c)throw std::logic_error("Unknown configured control");
  open(c->group);
 }
 // Shared field is a dependency of spatial optics, not of projection alone.
 for(const auto& id:configured) {
  const auto* c=findControl(id);std::string g=c->group;
  if(g=="focusField"||g=="detail"||g=="chromatic"||g=="offAxis"||g=="aperture"||g=="prism"||id=="geometryFieldAmount"||id=="peripheralStretch"||id=="peripheralWarp")open("fieldShape");
  if(id=="vignetteMechanical")open("imageCircle");
  if(id=="apertureResponse") {open("focusField");open("depthGroup");}
  if(id=="bloomEnergy"||id=="glareEnergy"||id=="sphericalHalo"||id=="coma"||id=="anamorphicFlareAmount")open("highlightResponse");
 }
 return result;
}
} // namespace LDBControlLayout
