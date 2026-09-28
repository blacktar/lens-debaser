# Model-driven lens profiles

Lens Debaser uses this hierarchy:

1. The runtime renderer defines supported optical behaviours and safe ranges.
2. A calibrated lens profile describes a real lens in that model space.
3. The profile compiler maps model-space terms to renderer controls.
4. Factory presets expose subtle, representative and exaggerated observations
   of one profile. Presets do not define renderer behaviour.

The first compiled profiles are Hawk V-Lite Vintage '74 and Cooke Anamorphic
/i Special Flare. Their source/streak/reflection/diffraction, pupil/bokeh and
field/imaging characteristics live in `scripts/lens_profiles.py`. The mapping
from semantic profile terms to runtime controls is deliberately centralized so
an engine-stage change cannot silently leave each preset with a different
interpretation.

Cooke also carries independent 32, 50, 75 and 100 mm calibration anchors.
Profile compilation linearly interpolates the structural flare observations
between adjacent anchors. Focal length is therefore a calibration axis, never
a substitute for preset strength. The generated `v1.41-Calibrate-Cooke-*`
fixtures expose the four measured anchors for reference comparison.

## Calibration rules

- Profile terms must correspond to an implemented renderer behaviour.
- Unknown terms fail generation instead of being ignored.
- Invariants describe lens construction shared by all observations.
- Observation tiers are separately calibrated; they are not global intensity
  multiplication.
- The representative tier is the primary reference match. Subtle is intended
  for ordinary grading, while Caricature exposes the signature for diagnosis.
- Image-space reference comparisons calibrate a profile. They do not add
  reference-specific branches to the renderer.

Future reference lenses should be added to this profile registry only after the
generic model can express their defining behaviour. If it cannot, improve the
model first, validate the new behaviour independently, then calibrate profiles.

## Future reference sources

- [CineTraits](https://cinetraits.com/) is a standing source for future engine
  feature research and lens-profile calibration. Its real-world tests,
  controlled lab tests, anamorphic and spherical coverage, focal-length sets,
  and side-by-side comparisons can help identify repeatable traits in flare,
  bokeh, field behaviour, contrast and colour.
- Use CineTraits material as perceptual reference evidence, alongside the local
  reference library and other documented sources. Confirm focal length,
  aperture, capture/processing conditions and licensing before deriving a
  profile or adding local assets.
- A reference may reveal a missing generic renderer capability; it must not
  justify a one-off preset-specific rendering branch. Improve and validate the
  top-level model first, then let that model drive the preset calibration.
