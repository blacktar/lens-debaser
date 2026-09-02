# LDB Optics engine ABI version 1

## Status

Frozen after Apple M1 functional, performance, cross-space, synthetic-chart,
iPhone DWG/Intermediate, and Alexa 35 LogC4 validation.

`LDBOpticsParameterABIVersion` is `1`. `LDBOpticsParameters` is a shared
host/Metal structure with a fixed size of 240 bytes and 16-byte alignment. The
size includes the native 16-byte alignment and padding of both `float3` color
fields; the wrapper must use this shared header rather than packing its own
copy.

## Compatibility rules

- Existing fields must not be reordered, removed, renamed in serialized preset
  keys, or changed to another numeric type during ABI version 1.
- New engine fields may consume reserved fields only when host and Metal are
  updated together and existing version-1 preset meaning remains unchanged.
- Any incompatible layout change requires a new ABI version and an explicit
  preset migration path.
- `LDBScatterParameters` is an internal host/Metal structure fixed at 32 bytes
  for version 1; it is not serialized in `.ldbpreset` files.
- Input Working Space and runtime `processingFlags` are not stored in lens
  presets.
- `astigmatism`, `radialSmear`, `tangentialSmear`, `coma`, and
  `sphericalHalo` are normalized perceptual controls whose useful range is
  contained in `-1...1` or `0...1` as appropriate. They must not require
  out-of-range test values.
- `processingFlags` contains the runtime Quality selection in bits 0–1 and
  Diagnostic View in bits 8–9. These remain excluded from `.ldbpreset` files.

## Neutral values

- All signed character/amount controls: `0.0`
- `opticalCenter`: `[0.5, 0.5]`
- `anamorphicSqueeze`: `1.0`
- `imageCircleSize`: `1.2`
- `imageCircleAspect`: `1.0`
- `imageCircleSoftness`: `0.1`
- `detailScale`: `1.0`
- `effectBlend`: `1.0`
- Transmission and glare colors: `[1.0, 1.0, 1.0]`

## Version-1 processing order

1. Decode selected working space and transform to linear AP1.
2. Geometry, chromatic displacement, off-axis focus, Detail Transfer, and coma.
3. Vignette and transmission.
4. Extract geometrically aligned highlight scatter from the direct image.
5. Independent bloom, glare, and spherical-halo scatter.
6. Composite and apply final effect blend.
7. Transform from AP1 and encode to the selected input working space.

Scatter extraction must remain aligned to the geometrically processed direct
image. Extracting from the original frame caused the rejected secondary-image
artifact when distortion and bloom/glare/halo were combined.

## Required regression gates

The version-1 ABI may be used by the OFX wrapper only while the complete engine
test suite passes, including neutral identity, bit-exact zero blend, five-space
equivalence, distortion-aligned scatter, continuous coma, smooth spherical halo,
Detail Transfer halo suppression, alpha preservation, normalized independent
astigmatism/smear, and the audit of every exposed UI control at values contained
inside its actual Resolve range. Legitimately subordinate controls are tested
with their documented parent amount enabled.
