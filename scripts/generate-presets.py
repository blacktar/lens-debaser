#!/usr/bin/env python3
"""Generate Lens Debaser's editable external factory preset libraries."""

from pathlib import Path
import shutil
import re
from lens_profiles import cooke_focal_calibrations, reference_lens_families

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "presets"
CURRENT_PRESET_TAG = "v1.68"
TIERS = (("1-Subtle", 0.35), ("2-Medium", 0.65), ("3-Caricature", 1.0))
GENERATED_PRESETS = set()

NEUTRAL = {
    "anamorphicSqueeze": 1.0, "captureFocalLength": 50.0,
    "captureAperture": 2.8, "captureFocusDistance": 300.0,
    "lookInfluence": 0.0, "imageCircleSize": 1.2,
    "imageCircleAspect": 1.0, "imageCircleSoftness": 0.1,
    "apertureRadius": 6.0, "apertureBladeCurvature": 0.5,
    "apertureSoftness": 0.5, "apertureAspect": 1.0,
    "apertureBokehSwirl": 0.0,
    "aperturePupilShift": 0.0, "aperturePupilClip": 0.0,
    "apertureRimWeight": 0.0,
    "fieldAspect": 1.0, "detailScale": 1.0,
    "comaThreshold": 0.6, "bloomThreshold": 1.0, "glareThreshold": 0.45,
    "bloomRadius": 12.0, "bloomHorizontalStretch": 1.0,
    "anamorphicFlareRadius": 80.0, "anamorphicFlareThreshold": 1.0,
    "anamorphicFlareCoreAmount": 0.0, "anamorphicFlareAsymmetry": 0.0,
    "anamorphicFlareGhostAmount": 0.0,
    "anamorphicFlareGhostPosition": -0.72,
    "anamorphicFlareGhostScale": 1.0,
    "anamorphicFlareBandAmount": 0.0,
    "anamorphicFlareBandSeparation": 48.0,
    "anamorphicFlareSecondaryAmount": 0.0,
    "anamorphicFlareSecondaryOffset": 180.0,
    "anamorphicFlareThickness": 1.0,
    "diffractionRayAmount": 0.0,
    "diffractionRayLength": 180.0,
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
    "internalDirtSoftness": 0.5, "internalDirtComplexity": 0.5,
    "anamorphicFlareR": 0.35, "anamorphicFlareG": 0.55,
    "anamorphicFlareB": 1.0,
    "anamorphicFlareGhostR": 0.55, "anamorphicFlareGhostG": 0.25,
    "anamorphicFlareGhostB": 1.0,
    "prismDistribution": 0, "prismEdgeBias": 0.65, "prismSoftness": 0.3,
}

FIXED = {"apertureShape", "apertureBladeCount", "depthMode", "captureGate",
         "prismDistribution",
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

def explicit_triplet(folder, order, family, recipes, note=""):
    """Write deliberately authored tiers without global strength scaling."""
    for number, tier in ((1, "Subtle"), (2, "Medium"), (3, "Caricature")):
        values = {**recipes[tier], **CINEMATIC_TIER_REVISIONS.get(order, {}).get(tier, {})}
        # Resolve review established that values below 1 produce an objectionably
        # abrupt field boundary. Preserve each recipe's relative intent while
        # moving cinematic falloffs into the gradual operating region.
        if 0 < values.get("responseFieldFalloff", 0) < 1:
            values["responseFieldFalloff"] += 1.0
        write(folder / f"{order:02d}-{family}-{number}-{tier}.ldbpreset",
              family, tier, values, note)

def recipes(shared, subtle, medium, caricature):
    return {tier: {**shared, **values} for tier, values in
            (("Subtle", subtle), ("Medium", medium),
            ("Caricature", caricature))}

# Resolve review showed that the first independently-authored Medium and
# Caricature recipes still converged visually. These are family-specific second
# passes, not a global multiplier: each tier pushes different signature traits.
CINEMATIC_TIER_REVISIONS = {
  1:{"Medium":{"cornerSharpnessLoss":.58,"fieldCurvature":.34,"glareEnergy":.18,"transmissionColorAmount":.28},"Caricature":{"cornerSharpnessLoss":.95,"fieldCurvature":.62,"longitudinalCA":.38,"glareEnergy":.38,"sphericalHalo":.32,"transmissionColorAmount":.48}},
  2:{"Medium":{"microContrast":-.38,"fineDetail":-.22,"cornerSharpnessLoss":.68,"sphericalHalo":.22,"transmissionColorAmount":.32},"Caricature":{"microContrast":-.72,"fineDetail":-.42,"cornerSharpnessLoss":1.12,"longitudinalCA":.52,"sphericalHalo":.55,"bloomEnergy":.42,"transmissionColorAmount":.52}},
  3:{"Medium":{"microContrast":-.55,"glareEnergy":.55,"glareRadius":88,"bloomEnergy":.46,"bloomThreshold":.40,"sphericalHalo":.38},"Caricature":{"microContrast":-.92,"glareEnergy":1.15,"glareRadius":125,"bloomEnergy":.9,"bloomThreshold":.20,"sphericalHalo":.9,"transmissionHighlightSoftness":1.6}},
  4:{"Medium":{"detailEdgeFalloff":.68,"cornerSharpnessLoss":.72,"astigmatism":.30,"lateralCARed":.72,"lateralCABlue":-.92,"variationAmount":.46},"Caricature":{"detailEdgeFalloff":1.15,"cornerSharpnessLoss":1.2,"astigmatism":.62,"radialSmear":.52,"lateralCARed":1.45,"lateralCABlue":-1.85,"variationAmount":.82}},
  5:{"Subtle":{"apertureResponse":.38,"apertureRadius":9,"apertureCatEye":.28,"apertureBokehSwirl":2.5,"fieldCurvature":.55},"Medium":{"apertureResponse":.65,"apertureRadius":13,"apertureCatEye":.50,"apertureBokehSwirl":4.0,"fieldCurvature":1.05},"Caricature":{"apertureResponse":.90,"apertureRadius":18,"apertureCatEye":.78,"apertureBokehSwirl":6,"fieldCurvature":1.6,"tangentialSmear":.85}},
  6:{"Subtle":{"apertureResponse":.36,"apertureRadius":9,"apertureAspect":1.08,"apertureCatEye":.34,"apertureBokehSwirl":2.3},"Medium":{"apertureResponse":.64,"apertureRadius":13,"apertureAspect":1.16,"apertureCatEye":.62,"apertureBokehSwirl":4.1},"Caricature":{"apertureResponse":.90,"apertureRadius":18,"apertureAspect":1.30,"apertureCatEye":.94,"apertureBokehSwirl":6,"astigmatism":1.1,"tangentialSmear":1.05}},
  7:{"Medium":{"apertureResponse":.50,"apertureRadius":11,"apertureRimWeight":.30,"sphericalHalo":.55,"fieldCurvature":.78},"Caricature":{"apertureRadius":15,"apertureResponse":.75,"apertureRimWeight":.55,"sphericalHalo":1.2,"fieldCurvature":1.35,"longitudinalCA":.75}},
  8:{"Medium":{"sphericalHalo":.9,"glareEnergy":.48,"bloomEnergy":.4,"transmissionHighlightSoftness":.9},"Caricature":{"sphericalHalo":1.8,"glareEnergy":.95,"bloomEnergy":.8,"transmissionHighlightSoftness":1.8,"cornerSharpnessLoss":.82}},
  9:{"Medium":{"anamorphicAberration":.9,"anamorphicFlareAmount":1.35,"anamorphicFlareThreshold":.30,"apertureAspect":2.4,"apertureBokehSwirl":2.2},"Caricature":{"anamorphicAberration":1.7,"anamorphicFlareAmount":2.2,"anamorphicFlareThreshold":.14,"apertureAspect":3.0,"apertureBokehSwirl":4.2,"lateralCARed":1.5,"lateralCABlue":-2}},
  10:{"Medium":{"anamorphicAberration":.72,"anamorphicFlareAmount":1.05,"anamorphicFlareThreshold":.32,"apertureAspect":1.9,"transmissionColorAmount":.28},"Caricature":{"anamorphicAberration":1.35,"anamorphicFlareAmount":1.8,"anamorphicFlareThreshold":.16,"apertureAspect":2.4,"apertureBokehSwirl":3.4,"transmissionColorAmount":.5}},
  11:{"Medium":{"cornerSharpnessLoss":.88,"fieldCurvature":.68,"anamorphicAberration":1.05,"tangentialSmear":.55,"apertureBokehSwirl":2.5},"Caricature":{"cornerSharpnessLoss":1.5,"fieldCurvature":1.2,"anamorphicAberration":1.9,"radialSmear":.72,"tangentialSmear":1.05,"apertureBokehSwirl":5}},
  12:{"Medium":{"anamorphicFlareAmount":1.55,"anamorphicFlareThreshold":.25,"bloomEnergy":.34,"glareEnergy":.42,"glareColorAmount":.5},"Caricature":{"anamorphicFlareAmount":2.5,"anamorphicFlareThreshold":.10,"bloomEnergy":.7,"glareEnergy":.9,"glareColorAmount":.9}},
  13:{"Medium":{"apertureResponse":.50,"apertureRadius":11,"apertureCatEye":.62,"apertureBokehSwirl":2.2,"aperturePupilShift":.10,"aperturePupilClip":.12,"coma":.42,"comaThreshold":.28},"Caricature":{"apertureResponse":.75,"apertureRadius":15,"apertureCatEye":.90,"apertureBokehSwirl":3.8,"aperturePupilShift":.20,"aperturePupilClip":.28,"coma":.85,"comaThreshold":.12,"fieldCurvature":.9}},
  14:{"Medium":{"distortionK1":-.018,"distortionK2":.10,"moustacheK3":.16,"cornerSharpnessLoss":.62,"lateralCARed":1.1,"lateralCABlue":-1.45,"radialSmear":.3},"Caricature":{"distortionK1":-.028,"distortionK2":.18,"moustacheK3":.28,"cornerSharpnessLoss":1.15,"lateralCARed":2.4,"lateralCABlue":-3,"radialSmear":.72,"astigmatism":.7}},
  15:{"Medium":{"cornerSharpnessLoss":.68,"fieldCurvature":.52,"variationAmount":.65,"variationFieldAsymmetry":.6,"variationChromaticAsymmetry":.75},"Caricature":{"cornerSharpnessLoss":1.2,"fieldCurvature":.95,"variationAmount":1,"variationFieldAsymmetry":1,"variationPupilIrregularity":.8,"variationChromaticAsymmetry":1.35}},
  16:{"Medium":{"imageCircleSize":.9,"vignetteMechanical":.28,"cornerSharpnessLoss":1.15,"coma":.48,"lateralCARed":1.65,"lateralCABlue":-2.1},"Caricature":{"imageCircleSize":.76,"vignetteMechanical":.52,"cornerSharpnessLoss":1.65,"coma":.95,"lateralCARed":3.1,"lateralCABlue":-3.8,"sphericalHalo":1}},
  17:{"Medium":{"captureInfluence":.9,"cornerSharpnessLoss":1.1,"fieldCurvature":1.05,"longitudinalCA":.82,"apertureResponse":.42,"apertureRadius":10},"Caricature":{"captureInfluence":1,"cornerSharpnessLoss":1.65,"fieldCurvature":1.55,"longitudinalCA":1.4,"apertureResponse":.65,"apertureRadius":14,"sphericalHalo":1}},
  18:{"Subtle":{"responseFieldOnset":.20,"cornerSharpnessLoss":.55,"fieldCurvature":.34,"astigmatism":.20,"lateralCARed":.38,"lateralCABlue":-.50},"Medium":{"responseFieldOnset":.14,"responseFieldFalloff":.34,"cornerSharpnessLoss":1.25,"fieldCurvature":1.0,"astigmatism":.65,"lateralCARed":1.35,"lateralCABlue":-1.75},"Caricature":{"responseFieldOnset":.08,"responseFieldFalloff":.24,"cornerSharpnessLoss":1.9,"fieldCurvature":1.65,"astigmatism":1.2,"lateralCARed":2.8,"lateralCABlue":-3.6}},
  19:{"Subtle":{"cornerSharpnessLoss":.82,"fieldCurvature":.74,"astigmatism":.52,"tangentialSmear":.40,"variationAmount":.34,"variationFieldAsymmetry":.50},"Medium":{"cornerSharpnessLoss":1.5,"fieldCurvature":1.4,"astigmatism":1.05,"tangentialSmear":.95,"variationAmount":.62,"variationFieldAsymmetry":1.0},"Caricature":{"cornerSharpnessLoss":2.0,"fieldCurvature":1.9,"astigmatism":1.6,"tangentialSmear":1.5,"lateralCARed":2.5,"lateralCABlue":-3.2,"variationAmount":1.0,"variationFieldAsymmetry":1.0}},
  20:{"Medium":{"apertureResponse":.52,"apertureRadius":12,"apertureBokehSwirl":2.8,"aperturePupilShift":.10,"apertureRimWeight":.28,"sphericalHalo":.8,"glareEnergy":.55,"variationPupilIrregularity":.85},"Caricature":{"apertureResponse":.75,"apertureRadius":15,"apertureBokehSwirl":4.8,"aperturePupilShift":.20,"aperturePupilClip":.14,"apertureRimWeight":.52,"sphericalHalo":1.5,"glareEnergy":1.1,"longitudinalCA":1.25,"variationPupilIrregularity":1}},
}

# New 1.37 stages are deliberately assigned only to families whose optical
# identity benefits from them. They are not a global "more vintage" layer.
NEW_STAGE_CHARACTER = {
  3:{"Subtle":{"frontHaze":.10,"coatingWear":.10,"damageScale":1.8,"damageSeed":1934},"Medium":{"frontHaze":.22,"cleaningMarks":.16,"coatingWear":.24,"damageScale":1.45,"damageSeed":1934},"Caricature":{"frontHaze":.42,"cleaningMarks":.38,"scratchAmount":.14,"coatingWear":.50,"damageScale":1.15,"damageSeed":1934}},
  4:{"Subtle":{"geometryFieldAmount":1,"peripheralWarp":.10},"Medium":{"geometryFieldAmount":1,"peripheralWarp":.22,"refractiveIrregularity":.16,"refractiveScale":2.6,"refractiveEdgeBias":.72,"refractiveSeed":1977},"Caricature":{"geometryFieldAmount":1,"peripheralWarp":.42,"refractiveIrregularity":.34,"refractiveScale":2.1,"refractiveEdgeBias":.62,"refractiveAnisotropy":.25,"refractiveRotation":7,"refractiveDispersion":.12,"refractiveSeed":1977}},
  11:{"Subtle":{"geometryFieldAmount":1,"peripheralWarp":.08,"refractiveIrregularity":.10,"refractiveScale":2.8,"refractiveEdgeBias":.78,"refractiveSeed":1958},"Medium":{"geometryFieldAmount":1,"peripheralWarp":.20,"refractiveIrregularity":.22,"refractiveScale":2.3,"refractiveEdgeBias":.68,"refractiveAnisotropy":.52,"refractiveRotation":4,"refractiveDispersion":.18,"refractiveSeed":1958},"Caricature":{"geometryFieldAmount":1,"peripheralWarp":.38,"refractiveIrregularity":.42,"refractiveScale":1.75,"refractiveEdgeBias":.58,"refractiveAnisotropy":.72,"refractiveRotation":9,"refractiveDispersion":.36,"refractiveSeed":1958}},
  14:{"Subtle":{"geometryFieldAmount":1,"peripheralStretch":.10,"peripheralWarp":.06},"Medium":{"geometryFieldAmount":1,"peripheralStretch":.22,"peripheralWarp":.16,"refractiveIrregularity":.12,"refractiveScale":2.8,"refractiveEdgeBias":.82,"refractiveDispersion":.12,"refractiveSeed":1414},"Caricature":{"geometryFieldAmount":1,"peripheralStretch":.38,"peripheralWarp":.30,"refractiveIrregularity":.28,"refractiveScale":2.2,"refractiveEdgeBias":.70,"refractiveAnisotropy":.25,"refractiveDispersion":.30,"refractiveSeed":1414}},
  15:{"Subtle":{"refractiveIrregularity":.08,"refractiveScale":3.1,"refractiveEdgeBias":.72,"refractiveSeed":13579},"Medium":{"refractiveIrregularity":.18,"refractiveScale":2.5,"refractiveEdgeBias":.62,"refractiveAnisotropy":.18,"refractiveDispersion":.10,"refractiveSeed":13579,"coatingWear":.08,"damageSeed":13579},"Caricature":{"refractiveIrregularity":.34,"refractiveScale":1.9,"refractiveEdgeBias":.54,"refractiveAnisotropy":.38,"refractiveDispersion":.24,"refractiveSeed":13579,"frontHaze":.12,"cleaningMarks":.12,"coatingWear":.20,"damageSeed":13579}},
  16:{"Subtle":{"geometryFieldAmount":1,"peripheralWarp":.12,"refractiveIrregularity":.10,"refractiveScale":1.8,"refractiveEdgeBias":.68,"refractiveSeed":42424},"Medium":{"geometryFieldAmount":1,"peripheralStretch":.12,"peripheralWarp":.28,"refractiveIrregularity":.25,"refractiveScale":1.35,"refractiveEdgeBias":.58,"refractiveDispersion":.20,"refractiveSeed":42424},"Caricature":{"geometryFieldAmount":1,"peripheralStretch":.24,"peripheralWarp":.52,"refractiveIrregularity":.48,"refractiveScale":.95,"refractiveEdgeBias":.46,"refractiveAnisotropy":.35,"refractiveDispersion":.48,"refractiveSeed":42424}},
  18:{"Subtle":{"refractiveIrregularity":.06,"refractiveScale":3.4,"refractiveEdgeBias":.86,"refractiveSeed":86420},"Medium":{"refractiveIrregularity":.14,"refractiveScale":2.7,"refractiveEdgeBias":.76,"refractiveAnisotropy":.30,"refractiveDispersion":.08,"refractiveSeed":86420},"Caricature":{"refractiveIrregularity":.28,"refractiveScale":2.0,"refractiveEdgeBias":.66,"refractiveAnisotropy":.55,"refractiveDispersion":.22,"refractiveSeed":86420}},
  20:{"Subtle":{"refractiveIrregularity":.10,"refractiveScale":2.6,"refractiveEdgeBias":.70,"refractiveSeed":20020,"frontHaze":.08,"coatingWear":.08,"damageSeed":20020},"Medium":{"refractiveIrregularity":.24,"refractiveScale":2.0,"refractiveEdgeBias":.58,"refractiveAnisotropy":.42,"refractiveDispersion":.14,"refractiveSeed":20020,"frontHaze":.18,"cleaningMarks":.14,"coatingWear":.22,"damageSeed":20020},"Caricature":{"refractiveIrregularity":.42,"refractiveScale":1.45,"refractiveEdgeBias":.48,"refractiveAnisotropy":.68,"refractiveDispersion":.34,"refractiveSeed":20020,"frontHaze":.34,"cleaningMarks":.32,"scratchAmount":.12,"coatingWear":.42,"damageSeed":20020}},
}

for family_order, tiers in NEW_STAGE_CHARACTER.items():
    for tier_name, additions in tiers.items():
        CINEMATIC_TIER_REVISIONS.setdefault(family_order, {}).setdefault(tier_name, {}).update(additions)

def write(path, family, tier, values, note):
    path.parent.mkdir(parents=True, exist_ok=True)
    values = dict(values)
    # ABI v17 gives Glare its own threshold. Preserve the authored response of
    # existing compound recipes while ensuring every newly generated glare
    # preset states its dependency explicitly.
    if values.get("glareEnergy", 0.0) > 0.0 and "glareThreshold" not in values:
        values["glareThreshold"] = values.get("bloomThreshold", NEUTRAL["glareThreshold"])
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
    content = "\n".join(lines) + "\n"
    GENERATED_PRESETS.add(path)
    if not path.exists() or path.read_text() != content:
        path.write_text(content)

def generate_demonstrations():
    d = OUT / "demonstrations"
    d.mkdir(parents=True, exist_ok=True)
    demos = [
      (1,"Demo-Capture",{"captureInfluence":1,"captureFocalLength":24,"captureAperture":1.6,"captureFocusDistance":90,"captureGate":1,"cornerSharpnessLoss":1.05,"fieldCurvature":.72,"longitudinalCA":.46,"vignetteNatural":.34},"Adds peripheral detail loss, field curvature, longitudinal focus color and natural vignetting, then lets the Capture settings coordinate their strength."),
      (2,"Demo-Look",{"lookInfluence":1,"lookCharacter":.76,"lookVintageBias":.62,"lookExoticBias":.34,"lookAnamorphicBias":.42},"A clearly visible coordinated look demonstrates the macro controls without overwhelming the underlying grade."),
      (3,"Demo-Field-Gated-Geometry",{"distortionK1":.016,"distortionK2":.030,"moustacheK3":.038,"geometryFieldAmount":.82,"opticalCenterX":.48,"opticalCenterY":.52,"fieldCenterX":.5,"fieldCenterY":.5,"fieldAspect":1,"responseFieldOnset":.26,"responseFieldFalloff":1.58},"A grid exposes controlled distortion developing gradually outside a protected centre."),
      (4,"Demo-Field-Shape",{"fieldAspect":1.9,"fieldRotation":28,"fieldCenterX":.42,"fieldCenterY":.57,"responseFieldOnset":.18,"responseFieldFalloff":1.24,"cornerSharpnessLoss":1.2,"fieldCurvature":.92,"astigmatism":.52,"lateralCARed":1.0,"lateralCABlue":-1.25},"Clear focus and chromatic dependencies make Field Center, Aspect, Rotation, Onset and Falloff visible."),
      (5,"Demo-Focus-And-Field",{"cornerSharpnessLoss":2.0,"astigmatism":1.05,"fieldCurvature":1.65,"radialSmear":.82,"tangentialSmear":1.28,"responseFieldOnset":.12,"responseFieldFalloff":1.12},"Fine texture reveals a clear gradual loss of peripheral definition and directional detail."),
      (6,"Demo-Detail-Transfer",{"microContrast":-.50,"fineDetail":-.34,"detailEdgeFalloff":.76,"sagittalDetail":.38,"tangentialDetail":-.34,"detailScale":2},"Fabric, foliage and resolution charts expose a visible directional detail response."),
      (7,"Demo-Chromatic-Aberration",{"lateralCARed":2.2,"lateralCABlue":-2.7,"chromaticFieldOnset":.22,"chromaticFieldFalloff":1.20,"longitudinalCA":.82,"longitudinalCARadius":8,"nearFocusR":1,"nearFocusG":.34,"nearFocusB":.76,"farFocusR":.32,"farFocusG":1,"farFocusB":.62},"High-contrast outer edges show clear but controlled lateral separation; defocused detail shows longitudinal color."),
      (8,"Demo-Anamorphic",{"anamorphicSqueeze":2,"anamorphicDistortion":.034,"anamorphicAberration":.76,"anamorphicFlareAmount":.92,"anamorphicFlareRadius":240,"anamorphicFlareThreshold":.42,"anamorphicFlareR":.18,"anamorphicFlareG":.46,"anamorphicFlareB":1},"Lines reveal cylindrical geometry while strong highlights reveal a controlled blue streak."),
      (9,"Demo-Aperture-And-Bokeh",{"responseFieldOnset":.14,"responseFieldFalloff":1.12,"apertureResponse":.76,"apertureRadius":15,"apertureShape":1,"apertureBladeCount":7,"apertureBladeCurvature":.56,"apertureRotation":14,"apertureSoftness":.22,"apertureCatEye":.56,"apertureAspect":1.18,"apertureBokehSwirl":2.8},"Point highlights clearly reveal a softly shaped seven-blade pupil, Cat-Eye and controlled tangential rotation."),
      (10,"Demo-Vignette",{"vignetteNatural":.46,"vignetteOptical":.30,"vignetteMechanical":.15},"The three attenuation types combine into a clear but grade-friendly edge falloff."),
      (11,"Demo-Image-Circle",{"vignetteMechanical":.62,"imageCircleSize":.90,"imageCircleAspect":1.42,"imageCircleSoftness":.26},"Mechanical Vignette is enabled so Size, Aspect and Softness clearly shape coverage without producing a hard tunnel."),
      (12,"Demo-Bloom",{"bloomEnergy":.65,"bloomThreshold":.50,"bloomRadius":54,"bloomHorizontalStretch":1.5},"Scene-linear highlights spread into a clearly visible bloom that preserves surrounding contrast."),
      (13,"Demo-Glare-And-Halo",{"glareEnergy":.58,"glareRadius":74,"glareColorAmount":.34,"glareR":1,"glareG":.72,"glareB":.46,"sphericalHalo":.58},"Bright practicals and windows reveal warm glare and a soft spherical halo."),
      (14,"Demo-Transmission",{"transmissionColorAmount":.40,"transmissionR":1,"transmissionG":.84,"transmissionB":.68,"transmissionDensity":.22,"transmissionContrast":-.30,"transmissionHighlightSoftness":.72},"Neutral greys, skin and highlights show a visible warm transmission bias and softer shoulder."),
      (15,"Demo-Highlight-Response",{"responseHighlightKnee":.72,"bloomEnergy":.38,"bloomThreshold":.72,"bloomRadius":28,"glareEnergy":.24,"glareRadius":44,"sphericalHalo":.20,"coma":.14,"comaThreshold":.68},"A moderate Highlight Knee coordinates neutral bloom, glare, halo and coma while preserving shadows and black borders."),
      (16,"Demo-Coma",{"coma":.82,"comaThreshold":.40,"sphericalHalo":.16},"Isolated bright points away from Field Center reveal a clear controlled asymmetric coma tail."),
      (17,"Demo-Variation",{"variationAmount":.60,"variationSeed":27183,"variationFieldAsymmetry":.46,"variationPupilIrregularity":.42,"variationChromaticAsymmetry":.55,"variationTransmissionUnevenness":.40,"fieldCurvature":.50,"apertureResponse":.28,"apertureRadius":9,"lateralCARed":.76,"lateralCABlue":-.94,"transmissionColorAmount":.26},"Compatible field, pupil, chromatic and transmission responses are enabled at clearly visible strengths; change Seed."),
      (18,"Demo-Depth-Input",{"depthMode":2,"depthNear":0,"depthFar":1,"depthFocus":.38,"responseDefocusOnset":.07,"responseDefocusFalloff":.40,"depthEdgeSoftness":.55,"responseScatterEdgeProtection":1,"apertureResponse":.50,"apertureRadius":11,"sphericalHalo":.24},"Connect a depth map to Second RGB; the recipe produces a neutral, clearly readable and protected depth transition without chromatic aberration."),
      (20,"Demo-Front-Element-Wear",{"frontHaze":.75,"cleaningMarks":.95,"scratchAmount":.40,"scratchDirection":28,"damageScale":1.35,"coatingWear":1.05,"coatingWearScale":1.45,"damageSeed":31415},"Highlights reveal cleaning haze, fixed wiping residue, sparse scratches and localized coating wear while ordinary detail retains useful contrast."),
      (21,"Demo-Refractive-Irregularity",{"refractiveIrregularity":.64,"refractiveScale":1.3,"refractiveEdgeBias":.56,"refractiveAnisotropy":.42,"refractiveRotation":18,"refractiveDispersion":.24,"refractiveSeed":27182},"A grid and high-contrast detail show clear stable local magnification variation with controlled wavelength separation."),
      (22,"Demo-Peripheral-Stretch",{"geometryFieldAmount":.82,"peripheralStretch":.32,"responseFieldOnset":.24,"responseFieldFalloff":1.58},"A grid clearly exposes radial magnification growing gradually toward the perimeter."),
      (23,"Demo-Peripheral-Warp",{"geometryFieldAmount":.82,"peripheralWarp":.40,"responseFieldOnset":.24,"responseFieldFalloff":1.58},"A grid exposes clear nonuniform edge bending while preserving the centre."),
      (24,"Demo-Internal-Element-Contamination",{"internalDirtAmount":4.0,"internalDirtScale":.62,"internalDirtSmear":.52,"internalDirtScatter":1.45,"internalDirtSoftness":.78,"internalDirtComplexity":.78,"internalDirtSeed":16180},"Localized internal contamination creates clearly visible cloudy density, elongated residue and illumination-driven veiling without becoming a global color treatment."),
      (25,"Demo-Bokeh-Swirl",{"responseFieldOnset":.09,"responseFieldFalloff":.92,"apertureResponse":.96,"apertureRadius":21,"apertureShape":0,"apertureSoftness":.18,"apertureCatEye":.76,"apertureBokehSwirl":8.0},"Point highlights clearly reveal filled outer pupils with pronounced tangential rotation."),
      (26,"Demo-Petzval-Field",{"responseFieldOnset":.11,"responseFieldFalloff":1.12,"fieldCenterX":.48,"fieldCenterY":.52,"cornerSharpnessLoss":1.6,"fieldCurvature":1.7,"astigmatism":.78,"tangentialSmear":.72,"apertureResponse":.88,"apertureRadius":18,"apertureShape":1,"apertureBladeCount":8,"apertureBladeCurvature":.72,"apertureSoftness":.20,"apertureCatEye":.80,"apertureAspect":1.16,"apertureBokehSwirl":5.0},"A central subject remains legible while curved focus and clear off-axis pupil shaping reinforce one another."),
      (27,"Demo-Structured-Anamorphic-Flare",{"anamorphicSqueeze":2,"anamorphicFlareAmount":.90,"anamorphicFlareRadius":1650,"anamorphicFlareThreshold":.50,"anamorphicFlareThickness":.15,"anamorphicFlareCoreAmount":.30,"anamorphicFlareAsymmetry":.07,"anamorphicFlareGhostAmount":.045,"anamorphicFlareGhostPosition":-.62,"anamorphicFlareGhostScale":.82,"anamorphicFlareGhostCount":3,"anamorphicFlareGhostSpacing":105,"anamorphicFlareGhostScaleDecay":.76,"anamorphicFlareGhostEnergyDecay":.54,"anamorphicFlareBandAmount":.45,"anamorphicFlareBandSeparation":26,"anamorphicFlareSecondaryAmount":.19,"anamorphicFlareSecondaryOffset":190,"anamorphicFlareR":.16,"anamorphicFlareG":.46,"anamorphicFlareB":1,"anamorphicFlareGhostR":.46,"anamorphicFlareGhostG":.28,"anamorphicFlareGhostB":1},"One compact bright source reveals a clear continuous streak and controlled reflection train."),
      (28,"Demo-Diffraction-Rays",{"anamorphicFlareAmount":.16,"anamorphicFlareThreshold":.54,"anamorphicFlareCoreAmount":.30,"diffractionRayAmount":.46,"diffractionRayLength":260,"glareEnergy":.11,"glareRadius":62},"Compact clipped highlights produce visible vertical diffraction rays with a continuous taper."),
      (29,"Demo-Pupil-Decenter-Clipping",{"responseFieldOnset":.14,"responseFieldFalloff":1.08,"apertureResponse":.54,"apertureRadius":12,"apertureShape":0,"apertureSoftness":.25,"aperturePupilShift":.38,"aperturePupilClip":.32},"Outer pupils visibly shift and close while retaining a smooth filled footprint."),
      (30,"Demo-Bubble-Rim-Bokeh",{"responseFieldOnset":.13,"responseFieldFalloff":1.10,"apertureResponse":.76,"apertureRadius":15,"apertureShape":0,"apertureSoftness":.16,"apertureCatEye":.28,"apertureBokehSwirl":1.1,"apertureRimWeight":.38},"Point highlights form a clear bubble rim around a filled pupil without overpowering the scene."),
      (31,"Demo-Prism-Refraction",{"prismDistribution":3,"prismAmount":.72,"prismDirection":0,"prismDispersion":.58,"fieldAspect":1.55,"fieldRotation":0,"responseFieldOnset":.22,"responseFieldFalloff":.92},"Straight lines and fine texture reveal a smooth radial prism displacement shaped by the shared Field controls."),
    ]
    for order,name,values,note in demos:
        write(d / f"{order:02d}-{name}.ldbpreset", name, "Educational", values, note)

def generate_lenses():
    d = OUT / "cinematic-lenses"
    d.mkdir(parents=True, exist_ok=True)
    families = [
      (1,"Golden-Portrait-Prime",recipes(
        {"responseFieldOnset":.28,"responseFieldFalloff":.62,"transmissionR":1,"transmissionG":.96,"transmissionB":.86},
        {"microContrast":.12,"fineDetail":.05,"cornerSharpnessLoss":.18,"fieldCurvature":.10,"lateralCARed":.12,"lateralCABlue":-.15,"transmissionColorAmount":.10,"glareEnergy":.05,"glareRadius":34},
        {"microContrast":.25,"fineDetail":.09,"cornerSharpnessLoss":.36,"fieldCurvature":.20,"astigmatism":.08,"lateralCARed":.24,"lateralCABlue":-.30,"longitudinalCA":.10,"transmissionColorAmount":.20,"transmissionHighlightSoftness":.22,"glareEnergy":.10,"glareRadius":40,"sphericalHalo":.07},
        {"microContrast":.38,"fineDetail":.12,"cornerSharpnessLoss":.58,"fieldCurvature":.34,"astigmatism":.16,"lateralCARed":.40,"lateralCABlue":-.50,"longitudinalCA":.20,"transmissionColorAmount":.32,"transmissionHighlightSoftness":.42,"glareEnergy":.18,"glareRadius":46,"sphericalHalo":.16}),
        "Warm dimensional separation; texture and bright edges reveal its field and glare character."),
      (2,"Silver-Contrast-Prime",recipes(
        {"responseFieldOnset":.25,"responseFieldFalloff":.68,"transmissionR":1,"transmissionG":.92,"transmissionB":.76},
        {"microContrast":-.10,"fineDetail":-.06,"cornerSharpnessLoss":.22,"fieldCurvature":.14,"lateralCARed":.15,"lateralCABlue":-.20,"transmissionColorAmount":.10,"transmissionContrast":-.05,"sphericalHalo":.05},
        {"microContrast":-.22,"fineDetail":-.13,"cornerSharpnessLoss":.45,"fieldCurvature":.30,"astigmatism":.10,"lateralCARed":.32,"lateralCABlue":-.42,"longitudinalCA":.16,"transmissionColorAmount":.20,"transmissionContrast":-.12,"transmissionHighlightSoftness":.28,"bloomEnergy":.10,"glareEnergy":.08,"sphericalHalo":.12},
        {"microContrast":-.38,"fineDetail":-.22,"cornerSharpnessLoss":.72,"fieldCurvature":.48,"astigmatism":.20,"lateralCARed":.55,"lateralCABlue":-.72,"longitudinalCA":.32,"transmissionColorAmount":.32,"transmissionContrast":-.22,"transmissionHighlightSoftness":.55,"bloomEnergy":.22,"glareEnergy":.18,"sphericalHalo":.24}),
        "Panchro-inspired warmth and restrained softness; fine edges and highlights reveal the response."),
      (3,"Uncoated-Newsreel",recipes(
        {"responseFieldOnset":.22,"responseFieldFalloff":.72,"transmissionR":1,"transmissionG":.88,"transmissionB":.66},
        {"microContrast":-.18,"fineDetail":-.08,"cornerSharpnessLoss":.16,"transmissionColorAmount":.14,"transmissionContrast":-.12,"bloomEnergy":.12,"bloomThreshold":.72,"glareEnergy":.15,"glareRadius":55,"sphericalHalo":.08},
        {"microContrast":-.38,"fineDetail":-.18,"cornerSharpnessLoss":.34,"fieldCurvature":.18,"lateralCARed":.28,"lateralCABlue":-.38,"transmissionColorAmount":.28,"transmissionDensity":.06,"transmissionContrast":-.30,"transmissionHighlightSoftness":.5,"bloomEnergy":.30,"bloomThreshold":.52,"bloomRadius":46,"glareEnergy":.34,"glareRadius":72,"sphericalHalo":.22},
        {"microContrast":-.68,"fineDetail":-.32,"cornerSharpnessLoss":.58,"fieldCurvature":.34,"lateralCARed":.62,"lateralCABlue":-.82,"longitudinalCA":.34,"transmissionColorAmount":.48,"transmissionDensity":.12,"transmissionContrast":-.58,"transmissionHighlightSoftness":1.05,"bloomEnergy":.62,"bloomThreshold":.34,"bloomRadius":62,"glareEnergy":.72,"glareRadius":96,"sphericalHalo":.48}),
        "Uncoated low-contrast glow; lamps, windows and reflections drive the strongest character."),
      (4,"Breathing-Documentary-Zoom",recipes(
        {"responseFieldOnset":.24,"responseFieldFalloff":.66,"transmissionR":1,"transmissionG":.91,"transmissionB":.74,"variationSeed":1977},
        {"distortionK1":.008,"distortionK2":.018,"microContrast":-.14,"fineDetail":-.08,"detailEdgeFalloff":.18,"cornerSharpnessLoss":.22,"lateralCARed":.18,"lateralCABlue":-.24,"transmissionColorAmount":.10,"variationAmount":.12,"variationTransmissionUnevenness":.18},
        {"distortionK1":.018,"distortionK2":.045,"microContrast":-.32,"fineDetail":-.20,"detailEdgeFalloff":.42,"cornerSharpnessLoss":.48,"astigmatism":.16,"radialSmear":.10,"lateralCARed":.45,"lateralCABlue":-.58,"transmissionColorAmount":.22,"bloomEnergy":.12,"glareEnergy":.10,"variationAmount":.28,"variationTransmissionUnevenness":.28},
        {"distortionK1":.032,"distortionK2":.085,"microContrast":-.58,"fineDetail":-.34,"detailEdgeFalloff":.78,"cornerSharpnessLoss":.78,"astigmatism":.32,"radialSmear":.24,"lateralCARed":.88,"lateralCABlue":-1.12,"transmissionColorAmount":.34,"bloomEnergy":.28,"glareEnergy":.24,"variationAmount":.48,"variationTransmissionUnevenness":.42}),
        "Uneven vintage zoom character; lines, fabric and edge detail reveal it best."),
      (5,"Rotating-Bokeh-Portrait",recipes(
        {"responseFieldOnset":.20,"responseFieldFalloff":.52,"fieldAspect":1.06},
        {"fieldCurvature":.34,"cornerSharpnessLoss":.38,"tangentialSmear":.08,"apertureResponse":.18,"apertureRadius":7.0,"apertureCatEye":.18,"apertureBokehSwirl":1.8,"longitudinalCA":.10},
        {"fieldCurvature":.68,"cornerSharpnessLoss":.72,"astigmatism":.18,"tangentialSmear":.20,"apertureResponse":.30,"apertureRadius":8.2,"apertureCatEye":.36,"apertureBokehSwirl":3.8,"longitudinalCA":.24,"sphericalHalo":.12},
        {"fieldCurvature":1.05,"cornerSharpnessLoss":1.12,"astigmatism":.36,"tangentialSmear":.38,"apertureResponse":.42,"apertureRadius":9.5,"apertureCatEye":.58,"apertureBokehSwirl":6.0,"longitudinalCA":.40,"sphericalHalo":.28}),
        "Tangentially rotating peripheral bokeh without image-structure swirl; point highlights reveal it best."),
      (6,"Petzval-Oval-Portrait",recipes(
        {"responseFieldOnset":.16,"responseFieldFalloff":.52,"fieldCenterX":.47,"fieldCenterY":.52,"apertureShape":1,"apertureBladeCount":8,"apertureBladeCurvature":.68,"transmissionR":1,"transmissionG":.9,"transmissionB":.72,"variationSeed":1860},
        {"fieldCurvature":.42,"cornerSharpnessLoss":.46,"astigmatism":.16,"tangentialSmear":.12,"apertureResponse":.18,"apertureRadius":7.0,"apertureCatEye":.28,"apertureAspect":1.05,"apertureBokehSwirl":1.4,"longitudinalCA":.14,"transmissionColorAmount":.10,"variationAmount":.14,"variationFieldAsymmetry":.18},
        {"fieldCurvature":.82,"cornerSharpnessLoss":.82,"astigmatism":.36,"tangentialSmear":.30,"apertureResponse":.30,"apertureRadius":8.2,"apertureCatEye":.52,"apertureAspect":1.12,"apertureBokehSwirl":3.2,"longitudinalCA":.30,"transmissionColorAmount":.20,"glareEnergy":.12,"variationAmount":.30,"variationFieldAsymmetry":.30},
        {"fieldCurvature":1.20,"cornerSharpnessLoss":1.22,"astigmatism":.62,"tangentialSmear":.54,"apertureResponse":.43,"apertureRadius":9.6,"apertureCatEye":.82,"apertureAspect":1.22,"apertureBokehSwirl":5.4,"longitudinalCA":.50,"transmissionColorAmount":.32,"glareEnergy":.28,"variationAmount":.50,"variationFieldAsymmetry":.44,"variationPupilIrregularity":.34}),
        "Warm asymmetric historical portrait glass; points and textured edges show its shaped pupil."),
      (7,"Bubble-Bokeh-Triplet",recipes(
        {"responseFieldOnset":.24,"responseFieldFalloff":.58,"apertureShape":0,"apertureSoftness":.08},
        {"fieldCurvature":.26,"cornerSharpnessLoss":.28,"apertureResponse":.12,"apertureRadius":6.3,"apertureCatEye":.08,"sphericalHalo":.12,"microContrast":-.06,"longitudinalCA":.10},
        {"fieldCurvature":.55,"cornerSharpnessLoss":.58,"astigmatism":.16,"radialSmear":.12,"apertureResponse":.23,"apertureRadius":7.4,"apertureCatEye":.18,"sphericalHalo":.32,"microContrast":-.16,"longitudinalCA":.24},
        {"fieldCurvature":.92,"cornerSharpnessLoss":.94,"astigmatism":.34,"radialSmear":.28,"tangentialSmear":.22,"apertureResponse":.38,"apertureRadius":8.8,"apertureCatEye":.30,"sphericalHalo":.68,"microContrast":-.30,"longitudinalCA":.44}),
        "Firm round defocus highlights; isolated bright points reveal the soap-bubble footprint."),
      (8,"Pearlescent-Diffusion",recipes(
        {"responseFieldOnset":.24,"responseFieldFalloff":.72},
        {"microContrast":-.14,"fineDetail":-.06,"cornerSharpnessLoss":.16,"fieldCurvature":.10,"sphericalHalo":.20,"glareEnergy":.10,"glareRadius":48,"bloomEnergy":.08,"bloomThreshold":.68,"transmissionContrast":-.06,"transmissionHighlightSoftness":.24},
        {"microContrast":-.34,"fineDetail":-.16,"cornerSharpnessLoss":.34,"fieldCurvature":.22,"sphericalHalo":.58,"glareEnergy":.28,"glareRadius":62,"bloomEnergy":.22,"bloomThreshold":.48,"bloomRadius":40,"longitudinalCA":.14,"transmissionContrast":-.18,"transmissionHighlightSoftness":.62},
        {"microContrast":-.62,"fineDetail":-.32,"cornerSharpnessLoss":.58,"fieldCurvature":.38,"sphericalHalo":1.30,"glareEnergy":.56,"glareRadius":76,"bloomEnergy":.44,"bloomThreshold":.30,"bloomRadius":52,"longitudinalCA":.30,"transmissionContrast":-.38,"transmissionHighlightSoftness":1.30}),
        "Luminous soft-focus response; bright edges drive glow while the centre remains usable."),
      (9,"Electric-Blue-Scope",recipes(
        {"anamorphicSqueeze":2,"fieldAspect":1.65,"responseFieldOnset":.20,"responseFieldFalloff":.58,"apertureShape":2,"apertureAspect":2,"anamorphicFlareR":.14,"anamorphicFlareG":.40,"anamorphicFlareB":1},
        {"anamorphicDistortion":.008,"anamorphicAberration":.28,"anamorphicFlareAmount":.48,"anamorphicFlareRadius":145,"anamorphicFlareThreshold":.62,"apertureResponse":.10,"apertureRadius":6.2,"apertureCatEye":.16,"apertureBokehSwirl":.5,"cornerSharpnessLoss":.20,"lateralCARed":.18,"lateralCABlue":-.24},
        {"anamorphicDistortion":.017,"anamorphicAberration":.64,"anamorphicFlareAmount":.95,"anamorphicFlareRadius":195,"anamorphicFlareThreshold":.42,"apertureResponse":.19,"apertureRadius":7.1,"apertureCatEye":.34,"apertureBokehSwirl":1.2,"astigmatism":.22,"cornerSharpnessLoss":.42,"fieldCurvature":.18,"lateralCARed":.45,"lateralCABlue":-.60},
        {"anamorphicDistortion":.028,"anamorphicAberration":1.12,"anamorphicFlareAmount":1.55,"anamorphicFlareRadius":245,"anamorphicFlareThreshold":.25,"apertureResponse":.31,"apertureRadius":8.3,"apertureCatEye":.56,"apertureBokehSwirl":2.2,"astigmatism":.48,"cornerSharpnessLoss":.72,"fieldCurvature":.36,"lateralCARed":.88,"lateralCABlue":-1.18}),
        "Blue 2x anamorphic character; bright points drive streaks and reveal oval peripheral bokeh."),
      (10,"Honeyed-Compact-Scope",recipes(
        {"anamorphicSqueeze":1.55,"fieldAspect":1.42,"responseFieldOnset":.22,"responseFieldFalloff":.62,"apertureShape":2,"apertureAspect":1.55,"anamorphicFlareR":1,"anamorphicFlareG":.50,"anamorphicFlareB":.12,"transmissionR":1,"transmissionG":.92,"transmissionB":.74},
        {"anamorphicDistortion":.006,"anamorphicAberration":.20,"anamorphicFlareAmount":.34,"anamorphicFlareRadius":125,"anamorphicFlareThreshold":.68,"apertureResponse":.09,"apertureRadius":6.1,"apertureCatEye":.12,"apertureBokehSwirl":.35,"cornerSharpnessLoss":.16,"transmissionColorAmount":.08},
        {"anamorphicDistortion":.013,"anamorphicAberration":.48,"anamorphicFlareAmount":.72,"anamorphicFlareRadius":165,"anamorphicFlareThreshold":.46,"apertureResponse":.17,"apertureRadius":6.9,"apertureCatEye":.26,"apertureBokehSwirl":.9,"cornerSharpnessLoss":.35,"fieldCurvature":.15,"longitudinalCA":.14,"transmissionColorAmount":.18,"glareEnergy":.08},
        {"anamorphicDistortion":.022,"anamorphicAberration":.86,"anamorphicFlareAmount":1.18,"anamorphicFlareRadius":205,"anamorphicFlareThreshold":.28,"apertureResponse":.28,"apertureRadius":8.0,"apertureCatEye":.44,"apertureBokehSwirl":1.7,"cornerSharpnessLoss":.60,"fieldCurvature":.30,"longitudinalCA":.30,"transmissionColorAmount":.32,"glareEnergy":.22}),
        "Warm 1.55x anamorphic response; highlights reveal amber streaks and elliptical bokeh."),
      (11,"Bent-Glass-Scope",recipes(
        {"anamorphicSqueeze":2,"fieldAspect":1.75,"responseFieldOnset":.15,"responseFieldFalloff":.54,"apertureShape":2,"apertureAspect":2.2},
        {"anamorphicDistortion":.010,"anamorphicAberration":.34,"anamorphicFlareAmount":.28,"anamorphicFlareRadius":155,"anamorphicFlareThreshold":.62,"cornerSharpnessLoss":.28,"fieldCurvature":.18,"tangentialSmear":.12,"apertureResponse":.10,"apertureRadius":6.2,"apertureCatEye":.20,"apertureBokehSwirl":.6,"lateralCARed":.24,"lateralCABlue":-.32},
        {"anamorphicDistortion":.022,"anamorphicAberration":.78,"anamorphicFlareAmount":.60,"anamorphicFlareRadius":205,"anamorphicFlareThreshold":.42,"astigmatism":.30,"cornerSharpnessLoss":.62,"fieldCurvature":.42,"radialSmear":.16,"tangentialSmear":.34,"apertureResponse":.20,"apertureRadius":7.2,"apertureCatEye":.42,"apertureBokehSwirl":1.5,"lateralCARed":.62,"lateralCABlue":-.82,"longitudinalCA":.16},
        {"anamorphicDistortion":.036,"anamorphicAberration":1.34,"anamorphicFlareAmount":1.02,"anamorphicFlareRadius":255,"anamorphicFlareThreshold":.26,"astigmatism":.68,"cornerSharpnessLoss":1.08,"fieldCurvature":.78,"radialSmear":.38,"tangentialSmear":.68,"apertureResponse":.33,"apertureRadius":8.5,"apertureCatEye":.72,"apertureBokehSwirl":2.9,"lateralCARed":1.20,"lateralCABlue":-1.55,"longitudinalCA":.36}),
        "Pronounced scope edge character around a protected elliptical centre; lines and highlights reveal it."),
      (12,"Neon-Radiance-Prime",recipes(
        {"anamorphicFlareR":.12,"anamorphicFlareG":.38,"anamorphicFlareB":1,"glareR":.28,"glareG":.55,"glareB":1,"transmissionR":.90,"transmissionG":.97,"transmissionB":1},
        {"anamorphicAberration":.10,"anamorphicFlareAmount":.55,"anamorphicFlareRadius":105,"anamorphicFlareThreshold":.62,"bloomEnergy":.08,"bloomThreshold":.66,"bloomRadius":24,"glareEnergy":.10,"glareRadius":34,"glareColorAmount":.14,"transmissionColorAmount":.04},
        {"anamorphicAberration":.24,"anamorphicFlareAmount":1.05,"anamorphicFlareRadius":145,"anamorphicFlareThreshold":.40,"bloomEnergy":.18,"bloomThreshold":.46,"bloomRadius":32,"glareEnergy":.24,"glareRadius":46,"glareColorAmount":.30,"transmissionColorAmount":.08,"transmissionHighlightSoftness":.16},
        {"anamorphicAberration":.42,"anamorphicFlareAmount":1.75,"anamorphicFlareRadius":185,"anamorphicFlareThreshold":.20,"bloomEnergy":.34,"bloomThreshold":.28,"bloomRadius":40,"glareEnergy":.46,"glareRadius":58,"glareColorAmount":.52,"transmissionColorAmount":.14,"transmissionContrast":.06,"transmissionHighlightSoftness":.36}),
        "Clean blue highlight radiance; lamps, reflections and bright windows are required to drive it."),
      (13,"Nocturnal-Cat-Eye",recipes(
        {"responseFieldOnset":.18,"responseFieldFalloff":.52,"apertureShape":1,"apertureBladeCount":9,"apertureBladeCurvature":.82,"apertureSoftness":.20,"apertureAspect":1.14},
        {"cornerSharpnessLoss":.20,"fieldCurvature":.12,"apertureResponse":.12,"apertureRadius":6.3,"apertureCatEye":.35,"apertureBokehSwirl":.7,"coma":.10,"comaThreshold":.55,"longitudinalCA":.08},
        {"cornerSharpnessLoss":.42,"fieldCurvature":.28,"apertureResponse":.22,"apertureRadius":7.2,"apertureCatEye":.68,"apertureBokehSwirl":1.7,"coma":.26,"comaThreshold":.38,"longitudinalCA":.18},
        {"cornerSharpnessLoss":.70,"fieldCurvature":.48,"apertureResponse":.35,"apertureRadius":8.5,"apertureCatEye":1.0,"apertureBokehSwirl":3.1,"coma":.52,"comaThreshold":.22,"longitudinalCA":.34}),
        "Peripheral cat-eye bokeh; small edge highlights are necessary to see the pupil footprint."),
      (14,"Stressed-Ultra-Wide",recipes(
        {"responseFieldOnset":.24,"responseFieldFalloff":.68},
        {"distortionK1":-.012,"distortionK2":.055,"moustacheK3":.08,"cornerSharpnessLoss":.16,"lateralCARed":.22,"lateralCABlue":-.28,"vignetteNatural":.04},
        {"distortionK1":-.028,"distortionK2":.14,"moustacheK3":.20,"cornerSharpnessLoss":.36,"astigmatism":.14,"radialSmear":.12,"lateralCARed":.55,"lateralCABlue":-.70,"vignetteNatural":.09,"vignetteMechanical":.04,"imageCircleSize":1.10,"imageCircleSoftness":.22},
        {"distortionK1":-.052,"distortionK2":.28,"moustacheK3":.40,"cornerSharpnessLoss":.68,"astigmatism":.34,"radialSmear":.34,"lateralCARed":1.08,"lateralCABlue":-1.34,"vignetteNatural":.16,"vignetteMechanical":.10,"imageCircleSize":1.04,"imageCircleSoftness":.20}),
        "Wide-angle moustache geometry; straight lines and high-contrast edges reveal the signature."),
      (15,"Rehoused-Still-Glass",recipes(
        {"responseFieldOnset":.22,"responseFieldFalloff":.64,"fieldCenterX":.47,"fieldCenterY":.53,"variationSeed":13579,"transmissionR":1,"transmissionG":.95,"transmissionB":.84},
        {"distortionK1":.006,"cornerSharpnessLoss":.18,"fieldCurvature":.12,"lateralCARed":.16,"lateralCABlue":-.20,"microContrast":-.06,"variationAmount":.18,"variationFieldAsymmetry":.18,"variationChromaticAsymmetry":.20,"transmissionColorAmount":.06},
        {"distortionK1":.014,"cornerSharpnessLoss":.40,"fieldCurvature":.28,"astigmatism":.16,"lateralCARed":.40,"lateralCABlue":-.52,"microContrast":-.16,"variationAmount":.42,"variationFieldAsymmetry":.34,"variationPupilIrregularity":.18,"variationChromaticAsymmetry":.42,"variationTransmissionUnevenness":.20,"transmissionColorAmount":.14},
        {"distortionK1":.026,"cornerSharpnessLoss":.68,"fieldCurvature":.52,"astigmatism":.34,"lateralCARed":.78,"lateralCABlue":-.98,"microContrast":-.28,"variationAmount":.78,"variationFieldAsymmetry":.58,"variationPupilIrregularity":.38,"variationChromaticAsymmetry":.78,"variationTransmissionUnevenness":.42,"transmissionColorAmount":.24}),
        "Decentered rehoused stills-lens character; edges and neutral surfaces reveal stable asymmetry."),
      (16,"C-Mount-CCTV",recipes(
        {"responseFieldOnset":.12,"responseFieldFalloff":.48,"variationSeed":42424,"transmissionR":.82,"transmissionG":1,"transmissionB":.76,"vignetteMechanical":.12,"imageCircleAspect":1.18,"imageCircleSoftness":.28},
        {"distortionK1":.035,"distortionK2":.018,"imageCircleSize":1.08,"cornerSharpnessLoss":.52,"fieldCurvature":.42,"lateralCARed":.55,"lateralCABlue":-.72,"coma":.12,"comaThreshold":.45,"transmissionColorAmount":.12,"variationAmount":.18,"variationChromaticAsymmetry":.28},
        {"distortionK1":.07,"distortionK2":.045,"imageCircleSize":.96,"cornerSharpnessLoss":.90,"fieldCurvature":.78,"radialSmear":.25,"lateralCARed":1.15,"lateralCABlue":-1.48,"longitudinalCA":.32,"coma":.28,"comaThreshold":.32,"sphericalHalo":.22,"transmissionColorAmount":.24,"variationAmount":.42,"variationFieldAsymmetry":.38,"variationChromaticAsymmetry":.68},
        {"distortionK1":.12,"distortionK2":.09,"imageCircleSize":.84,"cornerSharpnessLoss":1.35,"fieldCurvature":1.25,"radialSmear":.62,"tangentialSmear":.42,"lateralCARed":2.1,"lateralCABlue":-2.7,"longitudinalCA":.75,"coma":.62,"comaThreshold":.18,"sphericalHalo":.65,"transmissionColorAmount":.40,"variationAmount":.78,"variationFieldAsymmetry":.74,"variationChromaticAsymmetry":1.2}),
        "Small-format CCTV glass: visible image-circle pressure, green cast, colored edges and off-axis coma."),
      (17,"Close-Focus-Macro",recipes(
        {"responseFieldOnset":.18,"responseFieldFalloff":.52,"captureInfluence":.7,"captureFocalLength":100,"captureAperture":2,"captureFocusDistance":28},
        {"cornerSharpnessLoss":.48,"fieldCurvature":.40,"astigmatism":.10,"longitudinalCA":.28,"sphericalHalo":.12,"microContrast":.12,"fineDetail":.10},
        {"cornerSharpnessLoss":.88,"fieldCurvature":.78,"astigmatism":.26,"radialSmear":.15,"longitudinalCA":.58,"sphericalHalo":.30,"microContrast":.22,"fineDetail":.18,"apertureResponse":.18,"apertureRadius":7.2},
        {"cornerSharpnessLoss":1.35,"fieldCurvature":1.22,"astigmatism":.52,"radialSmear":.38,"tangentialSmear":.32,"longitudinalCA":1.05,"sphericalHalo":.68,"microContrast":.34,"fineDetail":.26,"apertureResponse":.34,"apertureRadius":9.2,"apertureCatEye":.38}),
        "Close-focus macro character with crisp central texture, rapidly curving focus and longitudinal color."),
      (18,"Microscope-Objective",recipes(
        {"fieldAspect":1.62,"fieldRotation":12,"responseFieldOnset":.24,"responseFieldFalloff":.58,"variationSeed":86420},
        {"cornerSharpnessLoss":.26,"fieldCurvature":.14,"astigmatism":.10,"lateralCARed":.16,"lateralCABlue":-.21,"variationAmount":.08,"variationFieldAsymmetry":.10},
        {"cornerSharpnessLoss":.62,"fieldCurvature":.38,"astigmatism":.28,"radialSmear":.08,"tangentialSmear":.18,"lateralCARed":.46,"lateralCABlue":-.60,"longitudinalCA":.10,"variationAmount":.18,"variationFieldAsymmetry":.18},
        {"cornerSharpnessLoss":1.16,"fieldCurvature":.76,"astigmatism":.54,"radialSmear":.20,"tangentialSmear":.42,"lateralCARed":.95,"lateralCABlue":-1.24,"longitudinalCA":.28,"variationAmount":.34,"variationFieldAsymmetry":.28}),
        "Microscope-objective character: a small clinical centre gives way to severe colored peripheral falloff."),
      (19,"Tilted-Freelens",recipes(
        {"fieldAspect":2.35,"fieldRotation":-31,"fieldCenterX":.38,"fieldCenterY":.59,"responseFieldOnset":.13,"responseFieldFalloff":.40,"variationSeed":19019},
        {"cornerSharpnessLoss":.62,"fieldCurvature":.55,"astigmatism":.38,"tangentialSmear":.28,"lateralCARed":.42,"lateralCABlue":-.58,"variationAmount":.22,"variationFieldAsymmetry":.34},
        {"cornerSharpnessLoss":1.05,"fieldCurvature":.95,"astigmatism":.72,"radialSmear":.22,"tangentialSmear":.58,"lateralCARed":.88,"lateralCABlue":-1.18,"longitudinalCA":.30,"variationAmount":.48,"variationFieldAsymmetry":.68,"variationChromaticAsymmetry":.42},
        {"cornerSharpnessLoss":1.55,"fieldCurvature":1.40,"astigmatism":1.15,"radialSmear":.48,"tangentialSmear":1.0,"lateralCARed":1.65,"lateralCABlue":-2.15,"longitudinalCA":.68,"sphericalHalo":.35,"variationAmount":.82,"variationFieldAsymmetry":1.0,"variationChromaticAsymmetry":.88}),
        "A deliberately tilted, decentered focus plane; faces and texture reveal its diagonal island of focus."),
      (20,"Improvised-Projector-Lens",recipes(
        {"responseFieldOnset":.12,"responseFieldFalloff":.44,"fieldCenterX":.54,"fieldCenterY":.46,"apertureShape":1,"apertureBladeCount":5,"apertureBladeCurvature":.15,"variationSeed":20020,"transmissionR":1,"transmissionG":.82,"transmissionB":.62},
        {"cornerSharpnessLoss":.55,"fieldCurvature":.48,"apertureResponse":.17,"apertureRadius":7.2,"apertureRotation":12,"apertureAspect":1.18,"apertureBokehSwirl":1.0,"longitudinalCA":.22,"sphericalHalo":.22,"glareEnergy":.15,"transmissionColorAmount":.14,"variationAmount":.20,"variationPupilIrregularity":.30},
        {"cornerSharpnessLoss":.95,"fieldCurvature":.88,"astigmatism":.42,"apertureResponse":.29,"apertureRadius":8.5,"apertureRotation":37,"apertureAspect":1.42,"apertureBokehSwirl":2.5,"longitudinalCA":.48,"lateralCARed":.72,"lateralCABlue":-.96,"sphericalHalo":.52,"glareEnergy":.34,"transmissionColorAmount":.28,"variationAmount":.46,"variationPupilIrregularity":.62,"variationTransmissionUnevenness":.34},
        {"cornerSharpnessLoss":1.42,"fieldCurvature":1.32,"astigmatism":.82,"radialSmear":.35,"tangentialSmear":.62,"apertureResponse":.42,"apertureRadius":9.8,"apertureRotation":71,"apertureAspect":1.75,"apertureBokehSwirl":4.5,"longitudinalCA":.88,"lateralCARed":1.45,"lateralCABlue":-1.9,"sphericalHalo":1.0,"glareEnergy":.68,"transmissionColorAmount":.46,"variationAmount":.78,"variationPupilIrregularity":1.0,"variationTransmissionUnevenness":.72}),
        "Improvised projection glass with an irregular five-sided pupil, colored glow and an off-axis focus island."),
      (22,"Hawk-V-Lite-Vintage-74",recipes(
        {"anamorphicSqueeze":2,"fieldAspect":1.72,"responseFieldOnset":.20,"responseFieldFalloff":1.58,
         "apertureShape":2,"apertureAspect":.48,
         "anamorphicFlareR":.22,"anamorphicFlareG":.52,"anamorphicFlareB":1,
         "anamorphicFlareGhostR":.30,"anamorphicFlareGhostG":.18,"anamorphicFlareGhostB":.68,
         "glareR":.18,"glareG":.42,"glareB":1},
        {"anamorphicDistortion":.009,"anamorphicAberration":.34,
         "anamorphicFlareAmount":.82,"anamorphicFlareRadius":1700,"anamorphicFlareThreshold":.58,
         "anamorphicFlareThickness":.35,
         "anamorphicFlareCoreAmount":.24,"anamorphicFlareAsymmetry":.04,
         "anamorphicFlareGhostAmount":.035,"anamorphicFlareGhostPosition":-.62,"anamorphicFlareGhostScale":.88,
         "anamorphicFlareBandAmount":.45,"anamorphicFlareBandSeparation":35,
         "anamorphicFlareSecondaryAmount":.14,"anamorphicFlareSecondaryOffset":210,
         "diffractionRayAmount":.05,"diffractionRayLength":115,
         "glareEnergy":.38,"glareRadius":420,"glareColorAmount":.62,
         "bloomEnergy":.055,"bloomThreshold":.62,"bloomRadius":38,
         "cornerSharpnessLoss":.24,"fieldCurvature":.15,"astigmatism":.10,
         "apertureResponse":.11,"apertureRadius":6.4,"apertureCatEye":.12,"apertureBokehSwirl":.08,
         "lateralCARed":.20,"lateralCABlue":-.28,"microContrast":-.06},
        {"anamorphicDistortion":.017,"anamorphicAberration":.72,
         "anamorphicFlareAmount":1.55,"anamorphicFlareRadius":2200,"anamorphicFlareThreshold":.42,
         "anamorphicFlareThickness":.18,
         "anamorphicFlareCoreAmount":.38,"anamorphicFlareAsymmetry":.08,
         "anamorphicFlareGhostAmount":.075,"anamorphicFlareGhostPosition":-.70,"anamorphicFlareGhostScale":.72,
         "anamorphicFlareBandAmount":1.72,"anamorphicFlareBandSeparation":48,
         "anamorphicFlareSecondaryAmount":.62,"anamorphicFlareSecondaryOffset":230,
         "diffractionRayAmount":.08,"diffractionRayLength":145,
         "glareEnergy":.78,"glareRadius":680,"glareColorAmount":.82,
         "bloomEnergy":.10,"bloomThreshold":.44,"bloomRadius":58,
         "cornerSharpnessLoss":.48,"fieldCurvature":.32,"astigmatism":.24,"tangentialSmear":.18,
         "apertureResponse":.20,"apertureRadius":7.4,"apertureCatEye":.32,"apertureBokehSwirl":.28,
         "lateralCARed":.48,"lateralCABlue":-.66,"longitudinalCA":.16,"microContrast":-.14},
        {"anamorphicDistortion":.026,"anamorphicAberration":1.22,
         "anamorphicFlareAmount":1.78,"anamorphicFlareRadius":2400,"anamorphicFlareThreshold":.24,
         "anamorphicFlareThickness":.14,
         "anamorphicFlareCoreAmount":.62,"anamorphicFlareAsymmetry":.16,
         "anamorphicFlareGhostAmount":.15,"anamorphicFlareGhostPosition":-.84,"anamorphicFlareGhostScale":.56,
         "anamorphicFlareBandAmount":2.0,"anamorphicFlareBandSeparation":55,
         "anamorphicFlareSecondaryAmount":1.10,"anamorphicFlareSecondaryOffset":255,
         "diffractionRayAmount":.16,"diffractionRayLength":190,
         "glareEnergy":1.38,"glareRadius":940,"glareColorAmount":1,
         "bloomEnergy":.24,"bloomThreshold":.28,"bloomRadius":74,
         "cornerSharpnessLoss":.82,"fieldCurvature":.58,"astigmatism":.48,"tangentialSmear":.42,
         "apertureResponse":.32,"apertureRadius":8.8,"apertureCatEye":.50,"apertureBokehSwirl":.65,
         "lateralCARed":.96,"lateralCABlue":-1.28,"longitudinalCA":.38,
         "microContrast":-.28,"transmissionHighlightSoftness":.42}),
        "Reference-inspired Hawk V-Lite Vintage '74 2x anamorphic character. Compact lamps drive the cool full-width streak, blue veil and restrained violet ghosts; the three variants use separately authored flare structures."),
      (23,"Cooke-Anamorphic-i-Special-Flare",recipes(
        {"anamorphicSqueeze":2,"fieldAspect":1.62,"responseFieldOnset":.18,"responseFieldFalloff":1.20,
         "apertureShape":2,"apertureAspect":.52,"apertureSoftness":.22,
         "anamorphicFlareR":.07,"anamorphicFlareG":.34,"anamorphicFlareB":1,
         "anamorphicFlareGhostR":.12,"anamorphicFlareGhostG":.52,"anamorphicFlareGhostB":1,
         "glareR":.08,"glareG":.34,"glareB":.78},
        {"anamorphicDistortion":.006,"anamorphicAberration":.24,
         "anamorphicFlareAmount":.72,"anamorphicFlareRadius":1650,"anamorphicFlareThreshold":.60,
         "anamorphicFlareThickness":.07,"anamorphicFlareCoreAmount":.18,"anamorphicFlareAsymmetry":.02,
         "anamorphicFlareGhostAmount":.012,"anamorphicFlareGhostPosition":.30,"anamorphicFlareGhostScale":1.42,
         "anamorphicFlareBandAmount":.18,"anamorphicFlareBandSeparation":14,
         "anamorphicFlareSecondaryAmount":.025,"anamorphicFlareSecondaryOffset":145,
         "diffractionRayAmount":.18,"diffractionRayLength":170,
         "glareEnergy":.16,"glareRadius":480,"glareColorAmount":.46,
         "bloomEnergy":.035,"bloomThreshold":.66,"bloomRadius":38,
         "cornerSharpnessLoss":.18,"fieldCurvature":.10,"astigmatism":.06,
         "apertureResponse":.10,"apertureRadius":6.2,"apertureCatEye":.14,"apertureBokehSwirl":.03,
         "lateralCARed":.14,"lateralCABlue":-.20,"microContrast":-.035},
        {"anamorphicDistortion":.012,"anamorphicAberration":.48,
         "anamorphicFlareAmount":1.50,"anamorphicFlareRadius":2100,"anamorphicFlareThreshold":.42,
         "anamorphicFlareThickness":.075,"anamorphicFlareCoreAmount":.30,"anamorphicFlareAsymmetry":.04,
         "anamorphicFlareGhostAmount":.035,"anamorphicFlareGhostPosition":.30,"anamorphicFlareGhostScale":1.48,
         "anamorphicFlareBandAmount":.38,"anamorphicFlareBandSeparation":18,
         "anamorphicFlareSecondaryAmount":.08,"anamorphicFlareSecondaryOffset":165,
         "diffractionRayAmount":.40,"diffractionRayLength":245,
         "glareEnergy":.62,"glareRadius":760,"glareColorAmount":.78,
         "bloomEnergy":.075,"bloomThreshold":.48,"bloomRadius":54,
         "cornerSharpnessLoss":.34,"fieldCurvature":.20,"astigmatism":.12,"tangentialSmear":.08,
         "apertureResponse":.18,"apertureRadius":7.0,"apertureCatEye":.26,"apertureBokehSwirl":.06,
         "lateralCARed":.32,"lateralCABlue":-.44,"longitudinalCA":.10,"microContrast":-.08},
        {"anamorphicDistortion":.020,"anamorphicAberration":.82,
         "anamorphicFlareAmount":1.80,"anamorphicFlareRadius":2250,"anamorphicFlareThreshold":.28,
         "anamorphicFlareThickness":.09,"anamorphicFlareCoreAmount":.46,"anamorphicFlareAsymmetry":.08,
         "anamorphicFlareGhostAmount":.09,"anamorphicFlareGhostPosition":.34,"anamorphicFlareGhostScale":1.72,
         "anamorphicFlareBandAmount":.75,"anamorphicFlareBandSeparation":24,
         "anamorphicFlareSecondaryAmount":.18,"anamorphicFlareSecondaryOffset":190,
         "diffractionRayAmount":.70,"diffractionRayLength":330,
         "glareEnergy":.82,"glareRadius":900,"glareColorAmount":.82,
         "bloomEnergy":.15,"bloomThreshold":.30,"bloomRadius":68,
         "cornerSharpnessLoss":.58,"fieldCurvature":.38,"astigmatism":.24,"tangentialSmear":.20,
         "apertureResponse":.29,"apertureRadius":8.2,"apertureCatEye":.46,"apertureBokehSwirl":.12,
         "lateralCARed":.64,"lateralCABlue":-.86,"longitudinalCA":.24,"microContrast":-.16}),
        "Reference-inspired Cooke Anamorphic /i Special Flare 2x character. A thin blue-cyan streak, compact white source, smooth vertical diffraction and broad cool wash surround a restrained analytic internal reflection. The ghost is a bounded lens-profile primitive and never a reprojected copy of scene highlights."),
    ]
    # Reference-calibrated families are compiled from the renderer's optical
    # model vocabulary.  Remove the historical inline recipes above while this
    # migration remains reviewable, then insert the model-owned profiles as the
    # sole generated source for these families.
    families = [family for family in families if family[0] not in (22, 23)]
    families.extend(reference_lens_families())
    families.extend([
      (24,"Decentered-Dream-Glass",recipes(
        {"fieldCenterX":.43,"fieldCenterY":.56,"responseFieldOnset":.14,
         "responseFieldFalloff":1.14,"apertureShape":1,"apertureBladeCount":7,
         "apertureBladeCurvature":.48,"apertureSoftness":.16,
         "transmissionR":1,"transmissionG":.88,"transmissionB":.76,
         "variationSeed":24571},
        {"cornerSharpnessLoss":.30,"fieldCurvature":.24,"astigmatism":.12,
         "apertureResponse":.24,"apertureRadius":8,"apertureAspect":1.08,
         "apertureCatEye":.20,"apertureBokehSwirl":1.0,"aperturePupilShift":.05,
         "aperturePupilClip":.04,"apertureRimWeight":.08,"longitudinalCA":.12,
         "transmissionColorAmount":.10,"variationAmount":.12,
         "variationFieldAsymmetry":.18,"variationPupilIrregularity":.16},
        {"cornerSharpnessLoss":.72,"fieldCurvature":.68,"astigmatism":.34,
         "tangentialSmear":.24,"apertureResponse":.52,"apertureRadius":12,
         "apertureAspect":1.16,"apertureCatEye":.46,"apertureBokehSwirl":2.8,
         "aperturePupilShift":.13,"aperturePupilClip":.12,"apertureRimWeight":.24,
         "longitudinalCA":.34,"lateralCARed":.38,"lateralCABlue":-.52,
         "sphericalHalo":.22,"transmissionColorAmount":.22,"variationAmount":.34,
         "variationFieldAsymmetry":.42,"variationPupilIrregularity":.42},
        {"cornerSharpnessLoss":1.25,"fieldCurvature":1.22,"astigmatism":.72,
         "radialSmear":.28,"tangentialSmear":.62,"apertureResponse":.78,
         "apertureRadius":16,"apertureAspect":1.28,"apertureCatEye":.78,
         "apertureBokehSwirl":4.8,"aperturePupilShift":.24,
         "aperturePupilClip":.26,"apertureRimWeight":.48,"longitudinalCA":.72,
         "lateralCARed":.88,"lateralCABlue":-1.16,"sphericalHalo":.62,
         "glareEnergy":.28,"transmissionColorAmount":.38,"variationAmount":.72,
         "variationFieldAsymmetry":.82,"variationPupilIrregularity":.78,
         "variationChromaticAsymmetry":.54}),
        "Decentered dream glass combining a displaced focus island, asymmetric clipped pupil, warm transmission and irregular seven-blade bokeh."),
      (25,"Prismatic-Night-Scope",recipes(
        {"anamorphicSqueeze":1.8,"fieldAspect":1.48,"responseFieldOnset":.18,
         "responseFieldFalloff":1.22,"apertureShape":2,"apertureAspect":1.8,
         "apertureSoftness":.18,"anamorphicFlareR":.22,"anamorphicFlareG":.48,
         "anamorphicFlareB":1,"anamorphicFlareGhostR":.22,
         "anamorphicFlareGhostG":.46,"anamorphicFlareGhostB":.82,
         "glareR":.24,"glareG":.46,"glareB":1},
        {"anamorphicDistortion":.008,"anamorphicAberration":.30,
         "anamorphicFlareAmount":.58,"anamorphicFlareRadius":1250,
         "anamorphicFlareThreshold":.58,"anamorphicFlareThickness":.14,
         "anamorphicFlareCoreAmount":.18,"anamorphicFlareGhostAmount":.018,
         "anamorphicFlareGhostPosition":-.38,"anamorphicFlareGhostScale":.95,
         "anamorphicFlareGhostCount":2,"anamorphicFlareGhostSpacing":95,
         "anamorphicFlareGhostScaleDecay":.82,"anamorphicFlareGhostEnergyDecay":.58,
         "anamorphicFlareBandAmount":.18,"anamorphicFlareBandSeparation":24,
         "diffractionRayAmount":.06,"diffractionRayLength":130,"glareEnergy":.16,
         "glareRadius":220,"glareColorAmount":.36,"apertureResponse":.14,
         "apertureRadius":7,"apertureCatEye":.18,"lateralCARed":.18,
         "lateralCABlue":-.28},
        {"anamorphicDistortion":.016,"anamorphicAberration":.68,
         "anamorphicFlareAmount":1.05,"anamorphicFlareRadius":1850,
         "anamorphicFlareThreshold":.36,"anamorphicFlareThickness":.13,
         "anamorphicFlareCoreAmount":.28,"anamorphicFlareAsymmetry":.10,
         "anamorphicFlareGhostAmount":.018,"anamorphicFlareGhostPosition":-.46,
         "anamorphicFlareGhostScale":1.25,"anamorphicFlareGhostCount":3,
         "anamorphicFlareGhostSpacing":150,"anamorphicFlareGhostScaleDecay":.78,
         "anamorphicFlareGhostEnergyDecay":.56,"anamorphicFlareBandAmount":.28,
         "anamorphicFlareBandSeparation":26,"anamorphicFlareSecondaryAmount":.08,
         "anamorphicFlareSecondaryOffset":205,"diffractionRayAmount":.08,
         "diffractionRayLength":170,"glareEnergy":.72,"glareRadius":650,
         "glareColorAmount":.55,"bloomEnergy":.18,"bloomThreshold":.38,
         "bloomRadius":65,"bloomHorizontalStretch":2.8,
         "apertureResponse":.32,"apertureRadius":10,"apertureCatEye":.38,
         "apertureBokehSwirl":1.4,"lateralCARed":.48,"lateralCABlue":-.68},
        {"anamorphicDistortion":.028,"anamorphicAberration":1.22,
         "anamorphicFlareAmount":1.65,"anamorphicFlareRadius":2000,
         "anamorphicFlareThreshold":.22,"anamorphicFlareThickness":.15,
         "anamorphicFlareCoreAmount":.46,"anamorphicFlareAsymmetry":.16,
         "anamorphicFlareGhostAmount":.035,"anamorphicFlareGhostPosition":-.54,
         "anamorphicFlareGhostScale":1.4,"anamorphicFlareGhostCount":4,
         "anamorphicFlareGhostSpacing":175,"anamorphicFlareGhostScaleDecay":.76,
         "anamorphicFlareGhostEnergyDecay":.54,"anamorphicFlareBandAmount":.55,
         "anamorphicFlareBandSeparation":34,"anamorphicFlareSecondaryAmount":.18,
         "anamorphicFlareSecondaryOffset":235,"diffractionRayAmount":.16,
         "diffractionRayLength":230,"glareEnergy":1.05,"glareRadius":850,
         "glareColorAmount":.72,"bloomEnergy":.32,"bloomThreshold":.24,
         "bloomRadius":85,"bloomHorizontalStretch":4.0,
         "apertureResponse":.55,"apertureRadius":14,"apertureCatEye":.62,
         "apertureBokehSwirl":2.8,"lateralCARed":1.0,"lateralCABlue":-1.35,
         "longitudinalCA":.38,"transmissionHighlightSoftness":.42}),
        "A creative 1.8x night scope with layered blue-violet streaks, a decaying prismatic reflection train, vertical diffraction and oval off-axis bokeh."),
    ])
    # The invented Prismatic Night Scope family was removed after Passes 81
    # and 82: it exposed analytic flare primitives without a convincing
    # reference-grounded optical identity. Do not ship a preset merely to fill
    # a catalogue slot.
    families = [family for family in families if family[0] != 25]
    # Replace the retired flare-driven night-scope recipe with a prism-led
    # optical family.  The supporting field, refractive and chromatic controls
    # keep the wedge integrated with the photographed image while the three
    # tiers remain useful starting points rather than calibration extremes.
    families.append(
      (25,"Edge-Prism-Glass",recipes(
        {"prismDirection":16,"responseFieldOnset":.20,
         "responseFieldFalloff":1.18,"chromaticFieldOnset":.24,
         "chromaticFieldFalloff":1.12},
        {"prismAmount":.24,"prismDispersion":.12,"prismEdgeBias":.72,
         "prismSoftness":.52,"refractiveIrregularity":.012,
         "refractiveScale":1.15,"refractiveEdgeBias":.78,
         "refractiveAnisotropy":.12,"refractiveRotation":16,
         "refractiveDispersion":.05,"cornerSharpnessLoss":.10,
         "lateralCARed":.08,"lateralCABlue":-.11,"microContrast":-.025},
        {"prismAmount":.62,"prismDispersion":.38,"prismEdgeBias":.58,
         "prismSoftness":.42,"refractiveIrregularity":.028,
         "refractiveScale":1.28,"refractiveEdgeBias":.70,
         "refractiveAnisotropy":.20,"refractiveRotation":16,
         "refractiveDispersion":.12,"cornerSharpnessLoss":.24,
         "fieldCurvature":.10,"tangentialSmear":.08,
         "lateralCARed":.20,"lateralCABlue":-.28,"microContrast":-.06},
        {"prismAmount":1.08,"prismDispersion":.82,"prismEdgeBias":.44,
         "prismSoftness":.32,"refractiveIrregularity":.060,
         "refractiveScale":1.45,"refractiveEdgeBias":.60,
         "refractiveAnisotropy":.32,"refractiveRotation":16,
         "refractiveDispersion":.24,"cornerSharpnessLoss":.48,
         "fieldCurvature":.22,"astigmatism":.12,"tangentialSmear":.18,
         "lateralCARed":.46,"lateralCABlue":-.62,"microContrast":-.12,
         "glareEnergy":.08,"glareRadius":34}),
        "A hand-held linear-prism character with a continuous one-sided bend, controlled spectral separation and softly integrated edge stress."))
    families.sort(key=lambda family: family[0])
    for order,name,values,note in families:
        explicit_triplet(d,order,name,values,note)

    # A single signature recipe rather than a strength family. This look was
    # deferred until the 1.37 peripheral and refractive stages could produce
    # progressive edge stress without relying on generic barrel distortion.
    write(d / "21-Bodycam-Edge-Stress.ldbpreset", "Bodycam Edge Stress",
          "Signature", {
        "geometryFieldAmount": 1,
        "peripheralStretch": .03,
        "peripheralWarp": .03,
        "distortionK1": -.012,
        "distortionK2": .040,
        "moustacheK3": .06,
        "responseFieldOnset": .16,
        "responseFieldFalloff": 1.10,
        "cornerSharpnessLoss": 2.0,
        "fieldCurvature": 1.75,
        "radialSmear": .55,
        "tangentialSmear": .72,
        "lateralCARed": 2.65,
        "lateralCABlue": -3.35,
        "chromaticFieldOnset": .22,
        "chromaticFieldFalloff": .68,
        "longitudinalCA": .30,
        "apertureResponse": 1.0,
        "apertureRadius": 20.0,
        "apertureCatEye": .30,
        "vignetteMechanical": 1.0,
        "imageCircleSize": 1.28,
        "imageCircleAspect": 1.0,
        "imageCircleSoftness": .06,
        "refractiveIrregularity": .15,
        "refractiveScale": 1.45,
        "refractiveEdgeBias": .90,
        "refractiveAnisotropy": .25,
        "refractiveRotation": -12,
        "refractiveDispersion": .32,
        "refractiveSeed": 28052023,
        "frontHaze": .12,
        "coatingWear": .12,
        "damageScale": 1.6,
        "damageSeed": 28052023,
    }, "Heavy but gradual bodycam edge stress: protected centre, local glass deformation, colored edge separation and mechanical image-circle pressure.")

    # Promoted after Resolve review of the internal-field reconstruction. This
    # is a single compound signature, not an unreviewed strength triplet.
    write(d / "26-Internal-Field-Edge-FX.ldbpreset", "Internal Field Edge FX",
          "Signature", {
        "fieldAspect": 1.58, "fieldRotation": 0,
        "fieldCenterX": .50, "fieldCenterY": .50,
        "responseFieldOnset": .24, "responseFieldFalloff": .82,
        "cornerSharpnessLoss": 1.42, "fieldCurvature": .72,
        "astigmatism": .20, "tangentialSmear": .28,
        "microContrast": -.18, "fineDetail": -.10,
        "apertureResponse": 1.0, "apertureRadius": 27,
        "apertureShape": 0, "apertureSoftness": .38,
        "prismDistribution": 3, "prismAmount": 0,
        "prismDirection": 0, "prismDispersion": 0,
        "lateralCARed": .82, "lateralCABlue": -1.04,
        "longitudinalCA": .14, "longitudinalCARadius": 5.5,
        "nearFocusR": .72, "nearFocusG": .34, "nearFocusB": 1.0,
        "farFocusR": .34, "farFocusG": 1.0, "farFocusB": .48,
    }, "Protected elliptical centre with smooth peripheral lens blur and restrained purple/green edge separation, built entirely from Lens Debaser's internal field.")

def generate_reference_calibrations():
    """Developer calibration fixtures; not user-facing strength presets."""
    # These anchors belong to the historical 1.41 flare model and must not be
    # mixed with current-build fixtures in Resolve's active tests folder.
    d = OUT / "archive" / "v1.41"
    for focal, values in cooke_focal_calibrations().items():
        write(d / f"v1.41-Calibrate-Cooke-Special-Flare-{focal}mm.ldbpreset",
              "Cooke Anamorphic /i Special Flare", f"Calibration {focal}mm",
              values, "Focal anchor compiled from the model-driven Cooke profile; compare against the matching T4 reference frame.")

def generate_abi16_smoke_tests():
    """Resolve-facing fixtures for current pupil, cloud and prism controls."""
    d = OUT / "tests"
    d.mkdir(parents=True, exist_ok=True)
    pupil_parent = {
        # Deliberately isolate the ABI-v15 pupil term.  A large circular base
        # footprint and short, still-smooth field ramp make the response
        # unambiguous on Resolve's point-highlight chart without cat-eye or
        # anamorphic shaping masking the control under test.
        "apertureResponse": 1.0, "apertureRadius": 24.0,
        "apertureShape": 0, "apertureAspect": 1.0,
        "apertureSoftness": .12, "apertureCatEye": 0.0,
        "apertureBokehSwirl": 0.0,
        "responseFieldOnset": 0.0, "responseFieldFalloff": .18,
    }
    cloud_parent = {
        "internalDirtAmount": 1.85, "internalDirtScale": 1.0,
        # These two fixtures isolate the density-field controls. Highlight
        # scatter is deliberately disabled: on a point/pupil chart it changes
        # the source footprint and can be mistaken for the cloud itself.
        "internalDirtSmear": .34, "internalDirtScatter": 0.0,
        "internalDirtSeed": 16180,
    }
    fixtures = (
        ("Pupil-Shift-Moderate", {**pupil_parent, "aperturePupilShift": .5},
         "Moderate isolated Pupil Shift. Outer pupils should move radially while the protected centre remains stable."),
        ("Pupil-Shift-Max", {**pupil_parent, "aperturePupilShift": 1.0},
         "Maximum isolated Pupil Shift. Compare with Moderate to confirm a continuous radial displacement rather than a stepped shape change."),
        ("Pupil-Clipping-Moderate", {**pupil_parent, "aperturePupilClip": .5},
         "Moderate isolated Pupil Clipping. Outer pupils should close asymmetrically without hard steps."),
        ("Pupil-Clipping-Max", {**pupil_parent, "aperturePupilClip": 1.0},
         "Maximum isolated Pupil Clipping. Compare with Moderate to confirm a continuous field and strength response."),
        ("Pupil-Rim-Weight-Neutral", {**pupil_parent, "apertureRimWeight": 0.0},
         "Neutral comparison for the two Rim Weight extremes on the same isolated pupil chart."),
        ("Pupil-Rim-Weight-Positive", {**pupil_parent, "apertureRimWeight": 1.0},
         "Maximum positive Rim Weight. Energy should form a smooth, clearly readable bubble rim without dots or scalloping."),
        ("Pupil-Rim-Weight-Negative", {**pupil_parent, "apertureRimWeight": -1.0},
         "Maximum negative Rim Weight. Energy should move smoothly toward the pupil centre without shrinking the footprint."),
        ("Cloud-Softness", {**cloud_parent, "internalDirtSoftness": .92,
                            "internalDirtComplexity": .50},
         "Use a scene with bright windows or practicals and fine detail. Cloud boundaries should change continuously without particles or painted-on defocus; move Cloud Softness from 0 to 1."),
        ("Cloud-Complexity", {**cloud_parent, "internalDirtSoftness": .72,
                              "internalDirtComplexity": 1.0},
         "Use a scene with bright windows or practicals. Complexity should modulate the broad density and veil without revealing individual blobs, noise or a sampling grid; compare 0 and 1."),
        ("Cloud-Amount-Conservative", {**cloud_parent, "internalDirtAmount": 1.0,
                                        "internalDirtSoftness": .72,
                                        "internalDirtComplexity": .75},
         "Conservative natural-range density. Compare on real footage against Medium and Extreme at Fit and 100%."),
        ("Cloud-Amount-Medium", {**cloud_parent, "internalDirtAmount": 5.0,
                                  "internalDirtSoftness": .72,
                                  "internalDirtComplexity": .75},
         "Pronounced extended-range density. It should remain smooth and retain image structure without Internal Scatter."),
        ("Cloud-Amount-Extreme", {**cloud_parent, "internalDirtAmount": 10.0,
                                   "internalDirtSoftness": .72,
                                   "internalDirtComplexity": .75},
         "Maximum creative-range density. It may approach black locally but must never invert, clip below zero, band or become unstable."),
        ("Bokeh-Swirl-Conservative", {"apertureResponse":1.0,"apertureRadius":14,"apertureShape":0,"apertureSoftness":.16,"apertureCatEye":.22,"apertureBokehSwirl":1.2,"responseFieldOnset":.16,"responseFieldFalloff":.72},
         "Use the isolated point-highlight chart. A restrained tangential pupil rotation should emerge smoothly outside the protected centre."),
        ("Bokeh-Swirl-Medium", {"apertureResponse":1.0,"apertureRadius":18,"apertureShape":0,"apertureSoftness":.16,"apertureCatEye":.42,"apertureBokehSwirl":3.2,"responseFieldOnset":.14,"responseFieldFalloff":.72},
         "Use the isolated point-highlight chart. Peripheral pupils should be clearly tangential and filled, without sparse streaks or repeated dots."),
        ("Bokeh-Swirl-Extreme", {"apertureResponse":1.0,"apertureRadius":40,"apertureShape":0,"apertureSoftness":.12,"apertureCatEye":.82,"apertureBokehSwirl":12.0,"responseFieldOnset":.10,"responseFieldFalloff":.72},
         "Use the isolated point-highlight chart. This creative limit must remain bounded, filled and continuous rather than collapsing into lines."),
        ("Petzval-Conservative", {"cornerSharpnessLoss":.42,"fieldCurvature":.38,"astigmatism":.10,"tangentialSmear":.08,"apertureResponse":.30,"apertureRadius":9,"apertureShape":1,"apertureBladeCount":8,"apertureBladeCurvature":.72,"apertureAspect":1.04,"apertureCatEye":.24,"apertureBokehSwirl":1.2,"responseFieldOnset":.18,"responseFieldFalloff":1.16},
         "Use a portrait or detailed central subject with peripheral lights. Look for a protected subject island, gradual curved focus and restrained rotating pupils."),
        ("Petzval-Medium", {"cornerSharpnessLoss":.82,"fieldCurvature":.82,"astigmatism":.30,"tangentialSmear":.24,"apertureResponse":.52,"apertureRadius":12,"apertureShape":1,"apertureBladeCount":8,"apertureBladeCurvature":.72,"apertureAspect":1.10,"apertureCatEye":.52,"apertureBokehSwirl":3.2,"responseFieldOnset":.16,"responseFieldFalloff":1.16},
         "Use a portrait or textured centre plus peripheral point highlights. Curved focus and pupil rotation should reinforce one another without globally smearing the subject."),
        ("Petzval-Extreme", {"cornerSharpnessLoss":1.32,"fieldCurvature":1.35,"astigmatism":.65,"tangentialSmear":.58,"apertureResponse":.78,"apertureRadius":16,"apertureShape":1,"apertureBladeCount":8,"apertureBladeCurvature":.66,"apertureAspect":1.18,"apertureCatEye":.88,"apertureBokehSwirl":6,"responseFieldOnset":.12,"responseFieldFalloff":1.10},
         "Use a portrait or textured centre plus peripheral point highlights. This creative extreme should retain a readable central island and smooth edge transition."),
        ("Prism-Conservative", {"prismAmount":.35,"prismDirection":12,"prismDispersion":.25,"prismEdgeBias":.62,"prismSoftness":.38},
         "Use a high-contrast chart and real footage with edge detail. Look for a restrained, smooth one-sided bend with light spectral separation."),
        ("Prism-Medium", {"prismAmount":.90,"prismDirection":16,"prismDispersion":.75,"prismEdgeBias":.52,"prismSoftness":.32},
         "Use a high-contrast chart and real footage. The prism edge should be obvious but continuous, without duplicated tiles, banding or a hard boundary."),
        ("Prism-Extreme", {"prismAmount":1.70,"prismDirection":20,"prismDispersion":1.50,"prismEdgeBias":.38,"prismSoftness":.22},
         "Creative limit test on a high-contrast chart. Displacement and spectral separation may be strong but must remain smooth, bounded and coherent."),
        ("Prism-Uniform", {"prismDistribution":1,"prismAmount":.65,"prismDirection":12,"prismDispersion":.45},
         "Uniform control case. The whole frame should move coherently without a spatial boundary or edge clamp streak."),
        ("Prism-Bilateral", {"prismDistribution":2,"prismAmount":.72,"prismDirection":0,"prismDispersion":.48,"fieldAspect":1.65,"fieldRotation":0,"responseFieldOnset":.22,"responseFieldFalloff":.78},
         "Both sides should refract smoothly in opposing directions while the central axis remains protected."),
        ("Prism-Radial", {"prismDistribution":3,"prismAmount":.72,"prismDirection":0,"prismDispersion":.48,"fieldAspect":1.65,"fieldRotation":0,"responseFieldOnset":.22,"responseFieldFalloff":.78},
         "Refraction should radiate smoothly from the elliptical Field Center and follow Aspect, Rotation, Onset and Falloff."),
        ("Prism-Inverse-Field", {"prismDistribution":4,"prismAmount":.72,"prismDirection":12,"prismDispersion":.48,"fieldAspect":1.35,"fieldRotation":-8,"responseFieldOnset":.18,"responseFieldFalloff":.68},
         "The prism response should be strongest inside the shaped central field and fade smoothly toward the perimeter."),
        ("Peripheral-Prism-Defocus", {"prismDistribution":3,"prismAmount":.46,"prismDirection":0,"prismDispersion":.36,"fieldAspect":1.72,"fieldRotation":0,"responseFieldOnset":.30,"responseFieldFalloff":.88,"cornerSharpnessLoss":1.12,"fieldCurvature":.48,"astigmatism":.18,"tangentialSmear":.18,"lateralCARed":.55,"lateralCABlue":-.72,"microContrast":-.18,"fineDetail":-.10},
         "Resolve-reference reconstruction: a wide central subject island with smooth peripheral defocus, radial prism displacement and controlled red/cyan edge separation."),
        ("Resolve-Edge-FX-Internal-Field", {
            "fieldAspect":1.58,"fieldRotation":0,"fieldCenterX":.50,"fieldCenterY":.50,
            "responseFieldOnset":.24,"responseFieldFalloff":.82,
            "cornerSharpnessLoss":1.42,"fieldCurvature":.72,"astigmatism":.20,
            "tangentialSmear":.28,"microContrast":-.18,"fineDetail":-.10,
            "apertureResponse":1.0,"apertureRadius":27,"apertureShape":0,
            "apertureSoftness":.38,
            "prismDistribution":3,"prismAmount":0,"prismDirection":0,
            "prismDispersion":0,"lateralCARed":.82,"lateralCABlue":-1.04,
            "longitudinalCA":.14,"longitudinalCARadius":5.5,
            "nearFocusR":.72,"nearFocusG":.34,"nearFocusB":1.0,
            "farFocusR":.34,"farFocusG":1.0,"farFocusB":.48},
         "Resolve-reference reconstruction using only Lens Debaser's internal elliptical Field: protected centre, smooth peripheral lens blur, radial prism displacement and restrained custom purple/green focus color."),
        ("Resolve-Edge-FX-Depth-Input", {
            "depthMode":2,"depthNear":0,"depthFar":1,"depthFocus":1,
            "responseDefocusOnset":.04,"responseDefocusFalloff":.56,
            "depthEdgeSoftness":.62,"responseScatterEdgeProtection":1,
            "apertureResponse":.68,"apertureRadius":12,"apertureShape":0,
            "apertureSoftness":.38,
            "fieldAspect":1.58,"fieldRotation":0,"fieldCenterX":.50,"fieldCenterY":.50,
            "responseFieldOnset":.24,"responseFieldFalloff":.82,
            "prismDistribution":3,"prismAmount":.09,"prismDirection":0,
            "prismDispersion":1.82,"lateralCARed":.62,"lateralCABlue":-.78,
            "longitudinalCA":.20,"longitudinalCARadius":5.5,
            "nearFocusR":.72,"nearFocusG":.34,"nearFocusB":1.0,
            "farFocusR":.34,"farFocusG":1.0,"farFocusB":.48},
         "Resolve-reference reconstruction using Second RGB as a feathered mask: white central ellipse stays focused, black periphery defocuses; radial prism and custom purple/green focus colors remain internal."),
    )
    for name, values, note in fixtures:
        write(d / f"{CURRENT_PRESET_TAG}-Smoke-{name}.ldbpreset", "ABI v18 Smoke",
              name.replace('-', ' '), values, note)

def archive_superseded_test_presets():
    """Keep only current-build fixtures in the active tests directory."""
    d = OUT / "tests"
    d.mkdir(parents=True, exist_ok=True)
    for path in sorted(d.glob("v*.ldbpreset")):
        # Conflict copies are never useful history; their canonical file is
        # either active or archived separately.
        if re.search(r" \d+$", path.stem):
            path.unlink()
            continue
        match = re.match(r"^(v\d+\.\d+)-", path.name)
        if not match or match.group(1) == CURRENT_PRESET_TAG:
            continue
        archive = OUT / "archive" / match.group(1)
        archive.mkdir(parents=True, exist_ok=True)
        destination = archive / path.name
        if destination.exists():
            path.unlink()
        else:
            path.replace(destination)

def purge_numbered_conflict_copies():
    """Remove Finder/File Provider numbered duplicates across active presets."""
    for folder in (OUT / "demonstrations", OUT / "cinematic-lenses",
                   OUT / "tests"):
        for path in folder.glob("*.ldbpreset"):
            if re.search(r" \d+$", path.stem):
                path.unlink()

def prune_stale_factory_presets():
    """Remove only obsolete generated factory files, preserving unchanged ones."""
    for folder in (OUT / "demonstrations", OUT / "cinematic-lenses"):
        for path in folder.glob("*.ldbpreset"):
            if path not in GENERATED_PRESETS:
                path.unlink()

def archive_factory_snapshot(version):
    """Preserve the prior shipped factory library once before regeneration."""
    destination = OUT / "archive" / version / "factory"
    if destination.exists():
        return
    destination.mkdir(parents=True)
    for folder_name in ("demonstrations", "cinematic-lenses"):
        source = OUT / folder_name
        if source.exists():
            shutil.copytree(source, destination / folder_name)

def readme():
    path = OUT / "README.md"
    content = """# Lens Debaser preset libraries

All files are editable plain-text `.ldbpreset` files. Loading one preset in a
folder populates Lens Debaser's Preset menu with every valid preset in that
same folder.

## demonstrations

Thirty single, moderate educational presets. Dependencies are intentionally enabled where a control would be
neutral on its own. `Demo-Depth-Input` requires a depth map on the dedicated
Depth Map RGB connector and assumes `Near Black` interpretation.

## cinematic-lenses

Twenty-six optical-character families, normally supplied at three strengths,
including reference-inspired Hawk V-Lite Vintage '74 and Cooke Anamorphic /i
Special Flare families, Decentered Dream Glass and Edge Prism Glass, plus one
independently authored Bodycam Edge Stress and Internal Field Edge FX signature
presets.
They are visual, behavior-inspired approximations rather than scientific lens
profiles or claims of exact matching. Caricature variants are diagnostic and
creative extremes; Medium is the best starting point; Subtle is intended for
ordinary finishing. Each strength is authored independently rather than made
by applying one global multiplier to a family recipe.

Processing settings such as Input Working Space and Diagnostic View are not
stored in these presets. Always set Input Working Space to match the image
entering Lens Debaser.
"""
    if not path.exists() or path.read_text() != content:
        path.write_text(content)

def validate_library():
    demos = sorted((OUT / "demonstrations").glob("*.ldbpreset"))
    lenses = sorted((OUT / "cinematic-lenses").glob("*.ldbpreset"))
    assert len(demos) == 30, f"expected 30 demonstration presets, found {len(demos)}"
    assert len(lenses) == 74, f"expected 74 cinematic presets, found {len(lenses)}"
    prism_lenses = [path for path in lenses if path.name.startswith("25-Edge-Prism-Glass-")]
    assert len(prism_lenses) == 3, "expected three Edge Prism Glass strength presets"
    for path in prism_lenses:
        values = dict(line.split("=", 1) for line in path.read_text().splitlines()
                      if line and not line.startswith("#") and "=" in line)
        assert float(values.get("prismAmount", 0.0)) > 0.0, \
            f"missing active prism response in {path.name}"
        assert float(values.get("prismSoftness", 0.0)) > 0.0, \
            f"missing continuous prism transition in {path.name}"
    for path in demos + lenses:
        assignments = [line for line in path.read_text().splitlines()
                       if line and not line.startswith("#") and "=" in line]
        assert len(assignments) > 1, f"empty preset: {path.name}"
    for path in lenses:
        values = dict(line.split("=", 1) for line in path.read_text().splitlines()
                      if line and not line.startswith("#") and "=" in line)
        response = float(values.get("apertureResponse", 0.0))
        radius = float(values.get("apertureRadius", NEUTRAL["apertureRadius"]))
        assert response <= 1.0, f"aperture response exceeds UI range in {path.name}"
        assert radius <= 48.0, f"aperture radius exceeds UI range in {path.name}"
        if response > 0:
            assert "responseFieldOnset" in values, f"missing focus onset in {path.name}"
            assert "responseFieldFalloff" in values, f"missing focus falloff in {path.name}"
            assert float(values["responseFieldFalloff"]) >= .40, f"unsafe abrupt focus falloff in {path.name}"
        assert float(values.get("apertureBokehSwirl", 0.0)) <= 12.0
    smoke = sorted((OUT / "tests").glob(f"{CURRENT_PRESET_TAG}-Smoke-*.ldbpreset"))
    assert len(smoke) == 28, f"expected 28 current-build smoke presets, found {len(smoke)}"
    smoke_names = [path.stem for path in smoke]
    assert len(smoke_names) == len(set(smoke_names)), "duplicate smoke preset filenames"

    # Duplicate prevention is library-wide. Finder and File Provider conflict
    # copies append a space and number while leaving the embedded Family /
    # Strength identity unchanged, so Resolve presents two indistinguishable
    # menu entries. Reject both that filename form and repeated identities in
    # every generated preset directory.
    for folder in (OUT / "demonstrations", OUT / "cinematic-lenses",
                   OUT / "tests"):
        identities = set()
        for path in sorted(folder.glob("*.ldbpreset")):
            assert not re.search(r" \d+$", path.stem), \
                f"numbered conflict-copy preset: {path.name}"
            metadata = {}
            for line in path.read_text().splitlines():
                if line.startswith("# Family: "):
                    metadata["family"] = line.removeprefix("# Family: ")
                elif line.startswith("# Strength: "):
                    metadata["strength"] = line.removeprefix("# Strength: ")
            # Legacy developer fixtures without display metadata remain
            # filename-addressed. Enforce embedded identity uniqueness where
            # the menu identity is actually present.
            if "family" in metadata and "strength" in metadata:
                identity = (metadata["family"], metadata["strength"])
                assert identity not in identities, \
                    f"duplicate preset identity in {folder.name}: {identity}"
                identities.add(identity)

    for path in (OUT / "tests").glob("v*.ldbpreset"):
        assert path.name.startswith(f"{CURRENT_PRESET_TAG}-"), \
            f"superseded build preset left active: {path.name}"

purge_numbered_conflict_copies()
archive_factory_snapshot("v1.55")
generate_demonstrations()
generate_lenses()
archive_superseded_test_presets()
generate_reference_calibrations()
generate_abi16_smoke_tests()
prune_stale_factory_presets()
readme()
purge_numbered_conflict_copies()
validate_library()
print("Generated 104 Lens Debaser factory presets.")
