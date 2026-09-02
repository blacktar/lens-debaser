# LDB Optics engine ABI version 2

ABI version 2 extends the validated version-1 engine with a neutral-by-default
aperture and pupil response. `LDBOpticsParameters` is shared verbatim by the
Apple host and Metal code, is 272 bytes, and retains 16-byte alignment.

The appended aperture fields are shape, blade count, response amount, response
radius, blade curvature, rotation, softness, cat-eye deformation, and pupil
aspect. Version-1 fields keep their original offsets and serialized preset
keys. Existing `.ldbpreset` files therefore load with the new fields at neutral
defaults.

## Neutral aperture state

- Shape: Circular
- Aperture Response: `0.0`
- Response Radius: `6.0`
- Blade Count: `6`
- Blade Curvature: `0.5`
- Rotation: `0.0` degrees
- Edge Softness: `0.5`
- Cat-Eye: `0.0`
- Pupil Aspect: `1.0`

## Required gates

The OFX wrapper may use ABI version 2 only while host and Metal compile against
the same shared header and regression tests verify neutral identity, independent
aperture response, distinct circular/polygon/oval shapes, blade count, blade
curvature, rotation, softness, pupil aspect, cat-eye deformation, preset
round-tripping, alpha preservation, and all version-1 optical and colour-space
requirements.
