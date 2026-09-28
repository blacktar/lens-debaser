#!/usr/bin/env python3
"""Calibrated lens profiles compiled into Lens Debaser renderer controls.

The runtime optical model owns the control vocabulary.  A lens profile records
measured/perceptual characteristics in grouped model space; it is not itself a
preset.  The preset generator asks this compiler for restrained, representative
and exaggerated observations of the same calibrated profile.
"""

from dataclasses import dataclass, field


TIERS = ("Subtle", "Medium", "Caricature")

# Profile-space names deliberately describe optical behaviour rather than UI
# labels.  This mapping is the single boundary between calibration and renderer.
CONTROL = {
    "squeeze": "anamorphicSqueeze", "field_aspect": "fieldAspect",
    "field_onset": "responseFieldOnset", "field_falloff": "responseFieldFalloff",
    "cylindrical_distortion": "anamorphicDistortion",
    "cylindrical_aberration": "anamorphicAberration",
    "streak_energy": "anamorphicFlareAmount", "streak_reach": "anamorphicFlareRadius",
    "source_threshold": "anamorphicFlareThreshold", "streak_width": "anamorphicFlareThickness",
    "source_core": "anamorphicFlareCoreAmount", "streak_asymmetry": "anamorphicFlareAsymmetry",
    "ghost_energy": "anamorphicFlareGhostAmount", "ghost_path": "anamorphicFlareGhostPosition",
    "ghost_scale": "anamorphicFlareGhostScale", "layer_energy": "anamorphicFlareBandAmount",
    "ghost_count": "anamorphicFlareGhostCount", "ghost_spacing": "anamorphicFlareGhostSpacing",
    "ghost_scale_decay": "anamorphicFlareGhostScaleDecay",
    "ghost_energy_decay": "anamorphicFlareGhostEnergyDecay",
    "layer_spacing": "anamorphicFlareBandSeparation", "secondary_energy": "anamorphicFlareSecondaryAmount",
    "secondary_offset": "anamorphicFlareSecondaryOffset", "ray_energy": "diffractionRayAmount",
    "ray_length": "diffractionRayLength", "veil_energy": "glareEnergy",
    "veil_radius": "glareRadius", "veil_color": "glareColorAmount",
    "bloom_energy": "bloomEnergy", "bloom_threshold": "bloomThreshold", "bloom_radius": "bloomRadius",
    "edge_loss": "cornerSharpnessLoss", "field_curvature": "fieldCurvature",
    "astigmatism": "astigmatism", "tangential_smear": "tangentialSmear",
    "red_lateral_ca": "lateralCARed", "blue_lateral_ca": "lateralCABlue",
    "axial_ca": "longitudinalCA", "microcontrast": "microContrast",
    "highlight_softness": "transmissionHighlightSoftness",
    "focal_length": "captureFocalLength",
    "pupil_shape": "apertureShape", "pupil_aspect": "apertureAspect",
    "pupil_softness": "apertureSoftness", "defocus_energy": "apertureResponse",
    "defocus_radius": "apertureRadius", "cat_eye": "apertureCatEye", "bokeh_swirl": "apertureBokehSwirl",
}


@dataclass(frozen=True)
class LensProfile:
    order: int
    name: str
    description: str
    invariant: dict
    observations: dict
    focal_anchors: dict = field(default_factory=dict)

    def compile(self):
        assert tuple(self.observations) == TIERS
        compiled = {}
        for tier in TIERS:
            model_values = {**self.invariant, **self.observations[tier]}
            unknown = sorted(set(model_values) - set(CONTROL))
            if unknown:
                raise ValueError(f"{self.name}: unknown profile terms: {unknown}")
            compiled[tier] = {CONTROL[key]: value for key, value in model_values.items()}
        return self.order, self.name, compiled, self.description

    def compile_at(self, focal_length, tier="Medium"):
        """Compile one tier with linearly interpolated focal calibration."""
        if not self.focal_anchors:
            raise ValueError(f"{self.name}: no focal calibration")
        anchors = sorted(self.focal_anchors)
        focal = min(max(float(focal_length), anchors[0]), anchors[-1])
        lower = max(value for value in anchors if value <= focal)
        upper = min(value for value in anchors if value >= focal)
        mix = 0.0 if lower == upper else (focal - lower) / (upper - lower)
        lower_values, upper_values = self.focal_anchors[lower], self.focal_anchors[upper]
        keys = set(lower_values) | set(upper_values)
        interpolated = {
            key: lower_values.get(key, upper_values[key]) * (1.0 - mix)
                 + upper_values.get(key, lower_values[key]) * mix
            for key in keys
        }
        model_values = {**self.invariant, **self.observations[tier],
                        **interpolated, "focal_length": focal}
        unknown = sorted(set(model_values) - set(CONTROL))
        if unknown:
            raise ValueError(f"{self.name}: unknown profile terms: {unknown}")
        return {CONTROL[key]: value for key, value in model_values.items()}


def _color(prefix, rgb):
    r, g, b = rgb
    return {f"{prefix}R": r, f"{prefix}G": g, f"{prefix}B": b}


def _with_colors(compiled, streak, ghost, veil):
    order, name, tiers, description = compiled
    colors = {**_color("anamorphicFlare", streak),
              **_color("anamorphicFlareGhost", ghost),
              **_color("glare", veil)}
    return order, name, {tier: {**values, **colors} for tier, values in tiers.items()}, description


HAWK_V_LITE_VINTAGE_74 = LensProfile(
    22, "Hawk-V-Lite-Vintage-74",
    "Model-calibrated Hawk V-Lite Vintage '74 2x profile. Compact lamps drive a cool full-width streak, blue veil, restrained violet reflection path and mild vertical diffraction.",
    {"squeeze": 2, "field_aspect": 1.72, "field_onset": .20, "field_falloff": 1.58,
     "pupil_shape": 2, "pupil_aspect": .48},
    {
      "Subtle": {"cylindrical_distortion":.009,"cylindrical_aberration":.34,"streak_energy":.82,"streak_reach":1700,"source_threshold":.58,"streak_width":.35,"source_core":.24,"streak_asymmetry":.04,"ghost_energy":.035,"ghost_path":-.62,"ghost_scale":.88,"layer_energy":.45,"layer_spacing":35,"secondary_energy":.14,"secondary_offset":210,"ray_energy":.05,"ray_length":115,"veil_energy":.38,"veil_radius":420,"veil_color":.62,"bloom_energy":.055,"bloom_threshold":.62,"bloom_radius":38,"edge_loss":.24,"field_curvature":.15,"astigmatism":.10,"defocus_energy":.11,"defocus_radius":6.4,"cat_eye":.12,"bokeh_swirl":.08,"red_lateral_ca":.20,"blue_lateral_ca":-.28,"microcontrast":-.06},
      "Medium": {"cylindrical_distortion":.017,"cylindrical_aberration":.72,"streak_energy":1.55,"streak_reach":2200,"source_threshold":.42,"streak_width":.18,"source_core":.38,"streak_asymmetry":.08,"ghost_energy":.075,"ghost_path":-.70,"ghost_scale":.72,"layer_energy":1.72,"layer_spacing":48,"secondary_energy":.62,"secondary_offset":230,"ray_energy":.08,"ray_length":145,"veil_energy":.78,"veil_radius":680,"veil_color":.82,"bloom_energy":.10,"bloom_threshold":.44,"bloom_radius":58,"edge_loss":.48,"field_curvature":.32,"astigmatism":.24,"tangential_smear":.18,"defocus_energy":.20,"defocus_radius":7.4,"cat_eye":.32,"bokeh_swirl":.28,"red_lateral_ca":.48,"blue_lateral_ca":-.66,"axial_ca":.16,"microcontrast":-.14},
      "Caricature": {"cylindrical_distortion":.026,"cylindrical_aberration":1.22,"streak_energy":1.78,"streak_reach":2400,"source_threshold":.24,"streak_width":.14,"source_core":.62,"streak_asymmetry":.16,"ghost_energy":.15,"ghost_path":-.84,"ghost_scale":.56,"layer_energy":2.0,"layer_spacing":55,"secondary_energy":1.10,"secondary_offset":255,"ray_energy":.16,"ray_length":190,"veil_energy":1.38,"veil_radius":940,"veil_color":1,"bloom_energy":.24,"bloom_threshold":.28,"bloom_radius":74,"edge_loss":.82,"field_curvature":.58,"astigmatism":.48,"tangential_smear":.42,"defocus_energy":.32,"defocus_radius":8.8,"cat_eye":.50,"bokeh_swirl":.65,"red_lateral_ca":.96,"blue_lateral_ca":-1.28,"axial_ca":.38,"microcontrast":-.28,"highlight_softness":.42},
    })


COOKE_ANAMORPHIC_SPECIAL_FLARE = LensProfile(
    23, "Cooke-Anamorphic-i-Special-Flare",
    "Model-calibrated Cooke Anamorphic /i Special Flare 2x profile. A thin blue-cyan streak, compact white source, continuous vertical diffraction and cool veil surround one restrained analytic reflection path.",
    {"squeeze":2,"field_aspect":1.62,"field_onset":.18,"field_falloff":1.20,
     "pupil_shape":2,"pupil_aspect":.52,"pupil_softness":.22},
    {
      "Subtle": {"cylindrical_distortion":.006,"cylindrical_aberration":.24,"streak_energy":.72,"streak_reach":1650,"source_threshold":.60,"streak_width":.07,"source_core":.18,"streak_asymmetry":.02,"ghost_energy":.012,"ghost_path":.30,"ghost_scale":1.42,"layer_energy":.18,"layer_spacing":14,"secondary_energy":.025,"secondary_offset":145,"ray_energy":.18,"ray_length":170,"veil_energy":.16,"veil_radius":480,"veil_color":.46,"bloom_energy":.035,"bloom_threshold":.66,"bloom_radius":38,"edge_loss":.18,"field_curvature":.10,"astigmatism":.06,"defocus_energy":.10,"defocus_radius":6.2,"cat_eye":.14,"bokeh_swirl":.03,"red_lateral_ca":.14,"blue_lateral_ca":-.20,"microcontrast":-.035},
      "Medium": {"cylindrical_distortion":.012,"cylindrical_aberration":.48,"streak_energy":1.50,"streak_reach":2100,"source_threshold":.42,"streak_width":.075,"source_core":.30,"streak_asymmetry":.04,"ghost_energy":.035,"ghost_path":.30,"ghost_scale":1.48,"layer_energy":.38,"layer_spacing":18,"secondary_energy":.08,"secondary_offset":165,"ray_energy":.40,"ray_length":245,"veil_energy":.62,"veil_radius":760,"veil_color":.78,"bloom_energy":.075,"bloom_threshold":.48,"bloom_radius":54,"edge_loss":.34,"field_curvature":.20,"astigmatism":.12,"tangential_smear":.08,"defocus_energy":.18,"defocus_radius":7.0,"cat_eye":.26,"bokeh_swirl":.06,"red_lateral_ca":.32,"blue_lateral_ca":-.44,"axial_ca":.10,"microcontrast":-.08},
      "Caricature": {"cylindrical_distortion":.020,"cylindrical_aberration":.82,"streak_energy":1.80,"streak_reach":2250,"source_threshold":.28,"streak_width":.09,"source_core":.46,"streak_asymmetry":.08,"ghost_energy":.09,"ghost_path":.34,"ghost_scale":1.72,"layer_energy":.75,"layer_spacing":24,"secondary_energy":.18,"secondary_offset":190,"ray_energy":.70,"ray_length":330,"veil_energy":.82,"veil_radius":900,"veil_color":.82,"bloom_energy":.15,"bloom_threshold":.30,"bloom_radius":68,"edge_loss":.58,"field_curvature":.38,"astigmatism":.24,"tangential_smear":.20,"defocus_energy":.29,"defocus_radius":8.2,"cat_eye":.46,"bokeh_swirl":.12,"red_lateral_ca":.64,"blue_lateral_ca":-.86,"axial_ca":.24,"microcontrast":-.16},
    },
    {
      # Calibrated from the supplied 32/50/75/100 mm T4 flare references.
      # These are structural observations, not strength settings.
      32: {"streak_energy":1.34,"streak_width":.085,"source_core":.40,
           "ghost_energy":.045,"ghost_path":-.10,"ghost_scale":.72,
           "ghost_count":5,"ghost_spacing":105,"ghost_scale_decay":.88,"ghost_energy_decay":.78,
           "layer_energy":.72,"layer_spacing":22,"secondary_energy":.16,
           "ray_energy":.25,"ray_length":245,"veil_energy":.56,"veil_radius":820},
      50: {"streak_energy":.82,"streak_width":.060,"source_core":.22,
           "ghost_energy":.010,"ghost_path":.15,"ghost_scale":.72,
           "ghost_count":1,"ghost_spacing":92,"ghost_scale_decay":.78,"ghost_energy_decay":.48,
           "layer_energy":.14,"layer_spacing":16,"secondary_energy":.025,
           "ray_energy":.12,"ray_length":190,"veil_energy":.25,"veil_radius":650},
      75: {"streak_energy":1.48,"streak_width":.072,"source_core":.34,
           "ghost_energy":.018,"ghost_path":-.85,"ghost_scale":.78,
           "ghost_count":2,"ghost_spacing":140,"ghost_scale_decay":.82,"ghost_energy_decay":.52,
           "layer_energy":.34,"layer_spacing":18,"secondary_energy":.07,
           "ray_energy":.30,"ray_length":235,"veil_energy":.66,"veil_radius":790},
      100:{"streak_energy":1.10,"streak_width":.065,"source_core":.28,
           "ghost_energy":.012,"ghost_path":-.40,"ghost_scale":1.05,
           "ghost_count":1,"ghost_spacing":110,"ghost_scale_decay":.80,"ghost_energy_decay":.50,
           "layer_energy":.24,"layer_spacing":17,"secondary_energy":.04,
           "ray_energy":.18,"ray_length":210,"veil_energy":.43,"veil_radius":720},
    })


def reference_lens_families():
    return [
        _with_colors(HAWK_V_LITE_VINTAGE_74.compile(), (.22,.52,1), (.30,.18,.68), (.18,.42,1)),
        _with_colors(COOKE_ANAMORPHIC_SPECIAL_FLARE.compile(), (.07,.34,1), (.12,.52,1), (.08,.34,.78)),
    ]


def cooke_focal_calibrations():
    colors = {**_color("anamorphicFlare", (.07,.34,1)),
              **_color("anamorphicFlareGhost", (.12,.52,1)),
              **_color("glare", (.08,.34,.78))}
    return {focal: {**COOKE_ANAMORPHIC_SPECIAL_FLARE.compile_at(focal), **colors}
            for focal in (32, 50, 75, 100)}
