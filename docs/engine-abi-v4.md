# LDB Optics engine ABI version 4

ABI version 4 appends neutral-by-default Field Shape and Transmission response
fields. Every version-1 through version-3 field retains its offset and meaning.
The shared `LDBOpticsParameters` structure is 560 bytes with 16-byte alignment.

## Field Shape

Field Shape is independent of Optical Center. Optical Center continues to
govern distortion, vignette and lateral chromatic displacement. Field Center,
Aspect and Rotation govern focus loss, field curvature, astigmatism, directional
smear, Detail Transfer direction and other off-axis character.

Neutral state:

- Field Center: `0.5, 0.5`
- Field Aspect: `1.0`
- Field Rotation: `0.0` degrees

Changing Field Shape without enabling a parent off-axis response must remain an
identity operation.

## Transmission response

The existing Transmission Color and Amount retain their meaning. Version 4
adds:

- Transmission Density, neutral `0.0`;
- Transmission Contrast, neutral `0.0`, pivoted around linear AP1 `0.18`;
- Transmission Highlight Softness, neutral `0.0`, preserving linear AP1 `0.18`.

Density represents uniform optical throughput. Contrast is a signed perceptual
response and Highlight Softness progressively compresses positive highlights.
Extended-range negative values remain finite and pass through highlight
softening unchanged.

## Anamorphic response

Anamorphic Distortion and Anamorphic Aberration are independent, signed
responses. Distortion applies unequal cylindrical field curvature without
resizing or desqueezing the image. Aberration creates horizontal red/blue
separation that remains independent of radial lateral chromatic aberration.

Both default to `0.0`. Existing Anamorphic Field retains its established role
as the aspect of the complete off-axis field.

Anamorphic Flare is a dedicated fourth scatter layer with independent Amount,
Radius, Threshold and Color. It extracts from the geometrically aligned direct
image, uses a wide horizontal and restrained vertical response, participates in
Diagnostic View, and follows the established softened
depth-occlusion policy. It does not require Bloom Amount and does not reuse
Bloom Stretch.

## Variation

Variation is deterministic and spatially stable. Variation Amount is the parent
blend and defaults to `0.0`; all child values are inert when it is zero.
Variation Seed is an integer lens-instance selector. Field Asymmetry modifies
an active off-axis response, Pupil Irregularity modifies an active aperture
footprint, Chromatic Asymmetry creates a decentered color displacement, and
Transmission Unevenness creates broad stable throughput variation.

The implementation contains no time input and therefore cannot flicker between
frames. Tests require identical output for repeated renders with the same seed
and distinct output for adjacent seeds.

## Advanced Responses

Advanced Responses are simultaneous envelope controls, not a mode selector.
They only reshape an enabled parent optical response and remain neutral by
themselves:

- Highlight Knee, default `0.0`, softens highlight eligibility around Bloom,
  Glare, Spherical Halo, Coma and Anamorphic Flare thresholds;
- Field Onset and Field Falloff, defaults `0.0` and `1.0`, reshape the spatial
  build-up of off-axis aberrations while reproducing the established field
  envelope at their defaults;
- Defocus Onset and Defocus Falloff, defaults `0.018` and `0.36`, reshape the
  depth distance over which Aperture Response, longitudinal chromatic
  aberration and Spherical Halo reach full strength;
- Scatter Edge Protection, default `1.0`, controls depth-boundary rejection for
  aperture reconstruction and optical scatter. At `0.0`, depth still controls
  defocus strength but no longer prevents cross-layer sampling.

## Capture and Look mappings

Capture is evaluated once on the host before Metal encoding. Focal Length and
Gate Width establish equivalent field coverage; Aperture scales pupil and
highlight sensitivity; Focus Distance scales close-focus character. Capture
Influence blends every multiplier back to exactly `1.0`, so zero influence
leaves all direct controls unchanged. Capture never creates an effect when its
corresponding direct amount is neutral.

Look is an additive macro layer. Character, Vintage Bias and Exotic Bias add
coordinated contributions to the visible direct model, multiplied by Look
Influence. They do not select hidden states or overwrite direct values. Look
Influence zero is an exact no-op, and subsequent direct-control edits remain
effective.

## Compatibility gates

- Existing offsets through `depthFar` remain unchanged.
- New fields occupy the version-3 tail padding and appended storage beginning at
  byte 360; this does not alter any version-3 field.
- Existing `.ldbpreset` files load all new controls at their neutral values.
- Neutral identity and zero Blend remain bit-exact.
- Field Center, Aspect and Rotation require independent-response tests with a
  documented parent effect enabled.
- Transmission Density, Contrast and Highlight Softness require independent
  response, extended-range and cross-working-space tests.
