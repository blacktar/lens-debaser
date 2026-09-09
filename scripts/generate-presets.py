#!/usr/bin/env python3
"""Generate Lens Debaser's editable external factory preset libraries."""

from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "presets"
TIERS = (("1-Subtle", 0.35), ("2-Medium", 0.65), ("3-Caricature", 1.0))

NEUTRAL = {
    "anamorphicSqueeze": 1.0, "captureFocalLength": 50.0,
    "captureAperture": 2.8, "captureFocusDistance": 300.0,
    "lookInfluence": 0.0, "imageCircleSize": 1.2,
    "imageCircleAspect": 1.0, "imageCircleSoftness": 0.1,
    "apertureRadius": 6.0, "apertureBladeCurvature": 0.5,
    "apertureSoftness": 0.5, "apertureAspect": 1.0,
    "fieldAspect": 1.0, "detailScale": 1.0,
    "comaThreshold": 0.6, "bloomThreshold": 1.0,
    "bloomRadius": 12.0, "bloomHorizontalStretch": 1.0,
    "anamorphicFlareRadius": 80.0, "anamorphicFlareThreshold": 1.0,
    "glareRadius": 24.0, "responseFieldFalloff": 1.0,
    "responseDefocusOnset": 0.018, "responseDefocusFalloff": 0.36,
    "responseScatterEdgeProtection": 1.0, "depthEdgeSoftness": 0.5,
    "effectBlend": 1.0, "depthFar": 1.0, "depthFocus": 0.5,
    "opticalCenterX": 0.5, "opticalCenterY": 0.5,
    "fieldCenterX": 0.5, "fieldCenterY": 0.5,
    "transmissionR": 1.0, "transmissionG": 1.0, "transmissionB": 1.0,
    "glareR": 1.0, "glareG": 1.0, "glareB": 1.0,
    "nearFocusR": 1.0, "nearFocusG": 0.35, "nearFocusB": 0.75,
    "farFocusR": 0.35, "farFocusG": 1.0, "farFocusB": 0.65,
    "anamorphicFlareR": 0.35, "anamorphicFlareG": 0.55,
    "anamorphicFlareB": 1.0,
}

FIXED = {"apertureShape", "apertureBladeCount", "depthMode", "captureGate",
         "variationSeed"}

def triplet(folder, order, family, target, note=""):
    for tier, strength in TIERS:
        values = {}
        for key, target_value in target.items():
            if key in FIXED:
                values[key] = target_value
            else:
                base = NEUTRAL.get(key, 0.0)
                values[key] = base + (target_value - base) * strength
        filename = f"{order:02d}-{family}-{tier}.ldbpreset"
        write(folder / filename, family, tier.split('-', 1)[1], values, note)

def write(path, family, tier, values, note):
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = ["LensDebaserPreset=2", f"# Family: {family}", f"# Strength: {tier}"]
    if note:
        lines.append(f"# {note}")
    for key in sorted(values):
        value = values[key]
        if isinstance(value, int):
            text = str(value)
        else:
            text = f"{value:.6f}".rstrip("0").rstrip(".")
        lines.append(f"{key}={text}")
    path.write_text("\n".join(lines) + "\n")

def generate_demonstrations():
    d = OUT / "demonstrations"
    if d.exists(): shutil.rmtree(d)
    families = [
      (1,"Demo-Capture",{"captureInfluence":1,"captureFocalLength":24,"captureAperture":1.2,"captureFocusDistance":70,"captureGate":5,"cornerSharpnessLoss":.9,"fieldCurvature":.55,"longitudinalCA":.35,"vignetteNatural":.22},"Capture Influence activates the capture-dependent response."),
      (2,"Demo-Geometry",{"distortionK1":.08,"distortionK2":.18,"moustacheK3":.22,"opticalCenterX":.47,"opticalCenterY":.53}),
      (3,"Demo-Field-Shape",{"anamorphicSqueeze":1.65,"fieldAspect":1.7,"fieldRotation":18,"fieldCenterX":.47,"fieldCenterY":.53}),
      (4,"Demo-Focus-And-Field",{"cornerSharpnessLoss":1.35,"astigmatism":.8,"fieldCurvature":1.1,"swirl":.7,"radialSmear":.55,"tangentialSmear":.75,"fieldAspect":1.25}),
      (5,"Demo-Detail-Transfer",{"microContrast":-.8,"fineDetail":-.65,"detailEdgeFalloff":1.25,"sagittalDetail":.55,"tangentialDetail":-.6,"detailScale":3}),
      (6,"Demo-Chromatic-Aberration",{"lateralCARed":2.2,"lateralCABlue":-2.8,"longitudinalCA":1.0,"longitudinalCARadius":7,"nearFocusR":1,"nearFocusG":.45,"nearFocusB":.8,"farFocusR":.45,"farFocusG":1,"farFocusB":.72}),
      (7,"Demo-Anamorphic",{"anamorphicDistortion":.055,"anamorphicAberration":.9,"anamorphicFlareAmount":1.2,"anamorphicFlareRadius":180,"anamorphicFlareThreshold":.7,"anamorphicFlareR":.25,"anamorphicFlareG":.48,"anamorphicFlareB":1}),
      (8,"Demo-Aperture",{"apertureResponse":1,"apertureRadius":18,"apertureShape":1,"apertureBladeCount":6,"apertureBladeCurvature":.2,"apertureRotation":20,"apertureSoftness":.3,"apertureCatEye":.65,"apertureAspect":1.25}),
      (9,"Demo-Vignette",{"vignetteNatural":.55,"vignetteOptical":.45,"vignetteMechanical":.3}),
      (10,"Demo-Image-Circle",{"imageCircleSize":.88,"imageCircleAspect":1.35,"imageCircleSoftness":.22}),
      (11,"Demo-Bloom",{"bloomEnergy":1.4,"bloomThreshold":.55,"bloomRadius":70,"bloomHorizontalStretch":2.2}),
      (12,"Demo-Glare-And-Halo",{"glareEnergy":.9,"glareRadius":85,"glareColorAmount":.35,"glareR":1,"glareG":.75,"glareB":.5,"sphericalHalo":1.0,"coma":.45,"comaThreshold":.45}),
      (13,"Demo-Transmission",{"transmissionColorAmount":.55,"transmissionR":1,"transmissionG":.84,"transmissionB":.63,"transmissionDensity":.55,"transmissionContrast":-.5,"transmissionHighlightSoftness":1.15}),
      (14,"Demo-Variation",{"variationAmount":1,"variationSeed":27183,"variationFieldAsymmetry":.65,"variationPupilIrregularity":.7,"variationChromaticAsymmetry":1.0,"variationTransmissionUnevenness":.6,"fieldCurvature":.55,"apertureResponse":.7,"apertureRadius":12,"lateralCARed":1.0,"lateralCABlue":-1.2,"transmissionColorAmount":.3}),
      (15,"Demo-Advanced-Responses",{"responseHighlightKnee":1.4,"responseFieldOnset":.32,"responseFieldFalloff":.62,"responseDefocusOnset":.08,"responseDefocusFalloff":.62,"responseScatterEdgeProtection":.35,"cornerSharpnessLoss":1.15,"fieldCurvature":.9,"bloomEnergy":.65,"bloomRadius":55,"apertureResponse":.7,"apertureRadius":14}),
      (16,"Demo-Depth-Input",{"depthMode":2,"depthNear":0,"depthFar":1,"depthFocus":.25,"depthEdgeSoftness":.2,"responseScatterEdgeProtection":1,"apertureResponse":1,"apertureRadius":18,"longitudinalCA":.45},"Requires a map connected to the dedicated Depth Map RGB input; assumes Near Black."),
    ]
    for order,name,values,*note in families: triplet(d,order,name,values,note[0] if note else "")

def generate_lenses():
    d = OUT / "cinematic-lenses"
    if d.exists(): shutil.rmtree(d)
    families = [
      (1,"Warm-Dimensional-Prime",{"microContrast":.35,"fineDetail":.12,"cornerSharpnessLoss":.55,"fieldCurvature":.28,"transmissionColorAmount":.3,"transmissionR":1,"transmissionG":.95,"transmissionB":.82,"transmissionHighlightSoftness":.38,"vignetteNatural":.12,"glareEnergy":.12,"glareRadius":42}),
      (2,"Classic-Panchro-Warmth",{"microContrast":-.28,"fineDetail":-.18,"cornerSharpnessLoss":.8,"astigmatism":.18,"fieldCurvature":.5,"lateralCARed":.5,"lateralCABlue":-.65,"longitudinalCA":.3,"vignetteNatural":.2,"bloomEnergy":.2,"glareEnergy":.16,"sphericalHalo":.18,"transmissionColorAmount":.3,"transmissionR":1,"transmissionG":.91,"transmissionB":.72,"transmissionContrast":-.18,"transmissionHighlightSoftness":.5}),
      (3,"Uncoated-Golden-Age",{"microContrast":-.65,"fineDetail":-.32,"cornerSharpnessLoss":.85,"fieldCurvature":.58,"lateralCARed":.8,"lateralCABlue":-1.05,"longitudinalCA":.42,"vignetteOptical":.22,"bloomEnergy":.55,"bloomThreshold":.55,"bloomRadius":58,"glareEnergy":.6,"glareRadius":90,"sphericalHalo":.38,"transmissionColorAmount":.45,"transmissionR":1,"transmissionG":.86,"transmissionB":.6,"transmissionDensity":.2,"transmissionContrast":-.6,"transmissionHighlightSoftness":1.0}),
      (4,"Seventies-Cinema-Zoom",{"distortionK1":.035,"distortionK2":.08,"microContrast":-.55,"fineDetail":-.35,"detailEdgeFalloff":.8,"cornerSharpnessLoss":.9,"astigmatism":.3,"radialSmear":.22,"lateralCARed":.85,"lateralCABlue":-1.1,"vignetteNatural":.22,"vignetteOptical":.18,"bloomEnergy":.28,"glareEnergy":.25,"transmissionColorAmount":.32,"transmissionR":1,"transmissionG":.9,"transmissionB":.7,"variationAmount":.45,"variationSeed":1977,"variationTransmissionUnevenness":.4}),
      (5,"Swirling-Portrait-Glass",{"swirl":1.25,"fieldCurvature":1.0,"cornerSharpnessLoss":1.25,"astigmatism":.42,"tangentialSmear":.38,"fieldAspect":1.08,"vignetteOptical":.22,"apertureResponse":.55,"apertureRadius":13,"apertureCatEye":.38,"sphericalHalo":.22}),
      (6,"Brass-Portrait-Swirl",{"swirl":1.65,"fieldCurvature":1.25,"cornerSharpnessLoss":1.5,"astigmatism":.6,"tangentialSmear":.55,"vignetteOptical":.3,"imageCircleSize":1.02,"imageCircleSoftness":.2,"apertureResponse":.75,"apertureRadius":16,"apertureShape":1,"apertureBladeCount":8,"apertureBladeCurvature":.7,"apertureCatEye":.48,"longitudinalCA":.35,"glareEnergy":.2}),
      (7,"Soap-Bubble-Triplet",{"fieldCurvature":1.0,"cornerSharpnessLoss":1.1,"astigmatism":.45,"radialSmear":.35,"tangentialSmear":.45,"apertureResponse":1,"apertureRadius":17,"apertureShape":0,"apertureSoftness":.12,"apertureCatEye":.32,"sphericalHalo":.5,"microContrast":-.35,"longitudinalCA":.35}),
      (8,"Dreamy-Soft-Focus",{"microContrast":-.75,"fineDetail":-.55,"sphericalHalo":1.15,"glareEnergy":.38,"glareRadius":65,"bloomEnergy":.28,"bloomThreshold":.65,"bloomRadius":45,"longitudinalCA":.28,"transmissionContrast":-.4,"transmissionHighlightSoftness":1.2,"vignetteNatural":.12}),
      (9,"Classic-Blue-2x-Scope",{"anamorphicSqueeze":2,"anamorphicDistortion":.045,"anamorphicAberration":1.0,"anamorphicFlareAmount":1.2,"anamorphicFlareRadius":220,"anamorphicFlareThreshold":.55,"anamorphicFlareR":.2,"anamorphicFlareG":.48,"anamorphicFlareB":1,"apertureResponse":.65,"apertureRadius":15,"apertureShape":2,"apertureAspect":2,"apertureCatEye":.5,"astigmatism":.45,"fieldAspect":1.5,"cornerSharpnessLoss":.65,"lateralCARed":.75,"lateralCABlue":-1.0,"vignetteOptical":.18}),
      (10,"Warm-Amber-Scope",{"anamorphicSqueeze":1.55,"anamorphicDistortion":.03,"anamorphicAberration":.65,"anamorphicFlareAmount":.8,"anamorphicFlareRadius":180,"anamorphicFlareThreshold":.7,"anamorphicFlareR":1,"anamorphicFlareG":.55,"anamorphicFlareB":.18,"apertureResponse":.55,"apertureRadius":14,"apertureShape":2,"apertureAspect":1.55,"apertureCatEye":.38,"cornerSharpnessLoss":.55,"transmissionColorAmount":.28,"transmissionR":1,"transmissionG":.92,"transmissionB":.73,"glareEnergy":.15}),
      (11,"Vintage-Scope-Edge-Warp",{"anamorphicSqueeze":2,"anamorphicDistortion":.065,"anamorphicAberration":1.25,"anamorphicFlareAmount":.7,"anamorphicFlareRadius":240,"astigmatism":.75,"fieldCurvature":.65,"cornerSharpnessLoss":1.1,"radialSmear":.45,"tangentialSmear":.7,"fieldAspect":1.7,"apertureResponse":.7,"apertureRadius":16,"apertureShape":2,"apertureAspect":2.2,"apertureCatEye":.7,"lateralCARed":1.2,"lateralCABlue":-1.5,"vignetteOptical":.28}),
      (12,"Controlled-Blue-Radiance",{"microContrast":.15,"fineDetail":.08,"anamorphicFlareAmount":.75,"anamorphicFlareRadius":150,"anamorphicFlareThreshold":.8,"anamorphicFlareR":.24,"anamorphicFlareG":.46,"anamorphicFlareB":1,"glareEnergy":.15,"glareRadius":45,"transmissionColorAmount":.12,"transmissionR":1,"transmissionG":.96,"transmissionB":.88,"transmissionContrast":.05,"transmissionHighlightSoftness":.3}),
      (13,"Cat-Eye-Nocturne",{"apertureResponse":1,"apertureRadius":19,"apertureShape":1,"apertureBladeCount":9,"apertureBladeCurvature":.8,"apertureSoftness":.3,"apertureCatEye":.85,"apertureAspect":1.12,"vignetteOptical":.28,"imageCircleSize":1.05,"cornerSharpnessLoss":.55,"coma":.38,"comaThreshold":.4}),
      (14,"Wide-Angle-Moustache",{"distortionK1":-.05,"distortionK2":.28,"moustacheK3":.42,"cornerSharpnessLoss":.75,"astigmatism":.35,"radialSmear":.4,"lateralCARed":1.1,"lateralCABlue":-1.35,"vignetteNatural":.28,"vignetteMechanical":.15,"imageCircleSize":1.04,"imageCircleSoftness":.18}),
      (15,"Asymmetric-Rehoused-Photo",{"distortionK1":.025,"cornerSharpnessLoss":.7,"fieldCurvature":.55,"astigmatism":.35,"lateralCARed":.75,"lateralCABlue":-.95,"vignetteOptical":.18,"microContrast":-.25,"variationAmount":.8,"variationSeed":13579,"variationFieldAsymmetry":.55,"variationPupilIrregularity":.4,"variationChromaticAsymmetry":.75,"variationTransmissionUnevenness":.45,"transmissionColorAmount":.2,"transmissionR":1,"transmissionG":.94,"transmissionB":.82}),
      (16,"Plastic-Fantasy-Optic",{"distortionK1":.09,"distortionK2":.22,"moustacheK3":.18,"cornerSharpnessLoss":1.55,"fieldCurvature":1.15,"swirl":.55,"radialSmear":.65,"tangentialSmear":.8,"lateralCARed":2.2,"lateralCABlue":-2.7,"longitudinalCA":.75,"vignetteMechanical":.28,"imageCircleSize":.96,"imageCircleAspect":1.15,"imageCircleSoftness":.12,"sphericalHalo":.55,"bloomEnergy":.32,"transmissionColorAmount":.3,"transmissionR":1,"transmissionG":.82,"transmissionB":.7,"variationAmount":.75,"variationSeed":42424,"variationFieldAsymmetry":.7,"variationChromaticAsymmetry":1.2}),
    ]
    for order,name,values in families: triplet(d,order,name,values,"Visual approximation; tune to the shot and working resolution.")

def readme():
    (OUT / "README.md").write_text("""# Lens Debaser preset libraries

All files are editable plain-text `.ldbpreset` files. Loading one preset in a
folder populates Lens Debaser's Preset menu with every valid preset in that
same folder.

## demonstrations

Sixteen control-group families, each supplied as Subtle, Medium and
Caricature. Dependencies are intentionally enabled where a control would be
neutral on its own. `Demo-Depth-Input` requires a depth map on the dedicated
Depth Map RGB connector and assumes `Near Black` interpretation.

## cinematic-lenses

Sixteen useful optical-character families, each supplied at three strengths.
They are visual, behavior-inspired approximations rather than scientific lens
profiles or claims of exact matching. Caricature variants are diagnostic and
creative extremes; Medium is the best starting point; Subtle is intended for
ordinary finishing.

Processing settings such as Input Working Space and Diagnostic View are not
stored in these presets. Always set Input Working Space to match the image
entering Lens Debaser.
""")

generate_demonstrations()
generate_lenses()
readme()
print("Generated 96 Lens Debaser presets.")
