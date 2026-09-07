# Lens Debaser optical model version 4

## Purpose

Version 4 completes the optical vocabulary before factory presets are created.
It preserves every existing OFX parameter ID and every version-1
`.ldbpreset` meaning. New fields are neutral by default and are appended to the
shared host/Metal parameter structure.

The model remains a fast perceptual approximation for grading. Capture
controls describe photographic context and drive documented response scaling;
they do not claim to reconstruct a physical lens prescription.

## Control layers

### Capture mapping

Capture is a deterministic mapping layer, not a second image-processing pass.

- **Focal Length** controls the strength and onset of off-axis effects.
- **Aperture** controls pupil-, defocus-, vignette- and highlight-response
  sensitivity.
- **Focus Distance** spans 1–1000 cm; the maximum represents infinity and
  controls close-focus character and breathing sensitivity.
- **Gate / Capture Format** establishes normalized field coverage used by focal
  length and image-circle calculations. The anamorphic entries approximate a
  full-frame gate's expanded horizontal field coverage and never desqueeze or
  overwrite direct Anamorphic controls.
- **Capture Influence** blends the mapping from zero to full strength. At zero,
  all existing direct controls retain exactly their current meaning.

Capture settings are lens-model inputs and are stored in `.ldbpreset` files.
Input Working Space remains a non-preset processing setting.

### Look mapping

Look provides a small number of coordinated, continuously adjustable macro
controls. It must never select a hidden preset or overwrite direct controls.
Character adds restrained opposing lateral colour. Vintage Bias adds stronger
lateral colour and soft longitudinal near/far colour alongside its transmission
and detail response. Exotic Bias combines lateral and longitudinal colour with
decentered chromatic variation and anamorphic separation. These contributions
are intentionally kept below detached RGB-ghost strength.

Vintage Caricature deliberately exaggerates the same family with stronger
detail loss, field curvature, astigmatism, coma, vignette, warm transmission,
longitudinal colour, bloom, glare and spherical halo.

Classic 2x Anamorphic Bias is a deliberately stylised cinema macro rather than
a measured branded-lens profile. It coordinates a 2x-shaped optical field,
cylindrical distortion, horizontal chromatic separation, blue horizontal flare,
stretched bloom and cat-eye/pupil character without desqueezing the image.
The renderer combines the macro contribution with the visible direct values so
the resulting state remains understandable and editable.

- **Character** increases the existing non-neutral optical responses in a
  balanced way.
- **Vintage Bias** shifts the balance toward lower transmission contrast,
  softer detail, warmer scatter and stronger field dependence.
- **Exotic Bias** shifts the balance toward asymmetry, pupil deformation,
  off-axis aberration and anamorphic character.
- **Look Influence** blends all macro contributions to zero.

## Direct optical groups

### Field Shape

Existing Field Curvature, Swirl, Radial Smear and Tangential Smear remain.
Version 4 adds a focus-field centre independent of Optical Center, plus field
aspect and rotation. This creates an editable sharp zone without incorrectly
moving distortion, vignette and chromatic centres at the same time.

Neutral values:

- Field Center X/Y: `0.5 / 0.5`
- Field Aspect: `1.0`
- Field Rotation: `0 degrees`

### Image Circle

Mechanical Vignette, Image Circle Size, Aspect and Softness are already
implemented. They move into a clearly labelled Image Circle subgroup without
changing their processing or serialized keys.

### Anamorphic

Existing Anamorphic Field, Oval / Anamorphic pupil, Pupil Aspect, Aperture
Rotation, Cat-Eye and Bloom Stretch remain. Version 4 adds independently
controllable anamorphic distortion, aberration and flare response so one global
field multiplier is no longer responsible for unrelated behaviours.

Neutral values:

- Anamorphic Distortion: `0.0`
- Anamorphic Aberration: `0.0`
- Anamorphic Flare: `0.0`
- Anamorphic Flare Threshold: `1.0`
- Anamorphic Flare Color: neutral white

These are visual lens responses, not an image squeeze/desqueeze operation.

### Transmission

Transmission Color and Amount remain. Version 4 adds independent density,
contrast and highlight softness. Density represents lens throughput and is
therefore allowed to change exposure; its neutral value remains a strict
bypass. Contrast and highlight softness operate in linear AP1 before scatter
extraction, with highlight softness preserving 18% middle grey.

Neutral values:

- Transmission Density: `0.0`
- Transmission Contrast: `0.0`
- Highlight Softness: `0.0`

### Variation

Variation models deterministic lens-to-lens imperfection. It is spatial, stable
over time and independent of image noise. The same seed and settings must
produce the same result on every frame and render.

- Variation Amount
- Variation Seed
- Field Asymmetry
- Pupil Irregularity
- Chromatic Asymmetry
- Transmission Unevenness

Variation Amount zero is bit-exact neutral. Seed is an integer selector, not a
slider that changes continuously during ordinary adjustment.

### Advanced Responses

Every response is shown as a labelled group; no selector hides multiple active
responses. Existing Coma, Spherical Halo, Longitudinal Amount, Aperture
Response, Bloom and Glare remain simultaneously editable.

Version 4 adds shared response shaping where it materially changes the image:

- highlight response knee;
- field response onset and falloff;
- defocus response onset and falloff;
- scatter edge protection.

The shaping controls modify their documented response envelopes. They do not
replace or multiplex the parent amount controls.

## Compatibility and validation

- Append fields only; never reorder the version-3 structure.
- All new amounts and influences default to zero.
- Existing neutral identity and zero-blend tests remain bit-exact.
- Existing `.ldbpreset` files load all version-4 fields at neutral defaults.
- New preset keys are plain text and unknown keys remain safely ignorable.
- Each new direct parameter requires an independent Metal test, an exposed UI
  range/dependency test and a visual reference that isolates its effect.
- Capture and Look mapping require tests proving zero influence is identical to
  the current direct model and proving direct controls remain editable.
- Variation requires deterministic repeatability, temporal stability and seed
  separation tests.
- Resolve validation must confirm group visibility, automatic expansion,
  animation, project persistence and practical 4K response on Apple Silicon.
