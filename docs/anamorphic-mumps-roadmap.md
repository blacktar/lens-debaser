# Anamorphic mumps exploration

## Finding

The current engine cannot reproduce anamorphic mumps as a distinct optical
response. It can create a static anamorphic-looking geometry treatment using
Anamorphic Distortion, ordinary radial distortion, field shaping and peripheral
softness, but this is not the defining behaviour of mumps.

Anamorphic mumps are a focus-dependent change in horizontal squeeze. On older
anamorphic designs, the effective squeeze can decrease toward close focus. If
the image is then desqueezed using the nominal lens ratio, centrally framed
subjects—most noticeably faces—appear wider. The effect changes during a focus
pull and should not be treated as generic edge distortion.

Current limitations:

- Anamorphic Distortion builds with radius and leaves the optical centre
  essentially unchanged.
- Anamorphic Squeeze shapes the spatial response of other effects and does not
  resize or desqueeze the image.
- Capture Focus Distance currently influences pupil, defocus, longitudinal
  colour and spherical-halo responses, but not anamorphic geometry or squeeze.
- The existing controls can therefore suggest cylindrical distortion but cannot
  produce focus-dependent facial widening.

## Future model to explore

Add a lightweight anisotropic coordinate mapping inside the existing geometry
stage rather than introducing another processing pass.

Candidate controls and behaviour:

- **Mumps Amount:** signed horizontal squeeze drift, with zero as strict
  identity and negative values available for inverse/corrective behaviour.
- **Close-Focus Response:** use Capture Focus Distance as the primary driver,
  with controllable onset and falloff.
- **Nominal Squeeze:** account for the current 1.33x, 1.5x, 1.55x, 1.8x and 2x
  lens character instead of applying one fixed correction.
- **Optical Centre:** anchor horizontal expansion around the existing Optical
  Center.
- **Field Distribution:** optionally blend between a uniform squeeze-ratio
  change and a centre-weighted creative approximation while keeping this
  separate from edge distortion.

The model should remain an image-space perceptual approximation, not a lens
prescription or scientific ray trace. A coordinate-only implementation should
have negligible cost compared with the existing blur, aperture and scatter
stages.

## Validation requirements

- Verify strict neutral identity at zero amount.
- Use a centred face or head-and-shoulders reference at multiple simulated
  focus distances; charts alone are insufficient for judging the characteristic.
- Confirm progressive horizontal widening toward close focus without unintended
  vertical scaling.
- Animate Capture Focus Distance and confirm a smooth, temporally stable focus
  pull without stepping or edge discontinuities.
- Test multiple nominal squeeze ratios and both positive and corrective signed
  responses.
- Confirm Optical Center offsets remain stable and predictable.
- Compare the dedicated response against existing Anamorphic Distortion to
  ensure the two controls remain visually and conceptually independent.
- Benchmark the geometry-only addition and require no new render pass.

## References

- *American Cinematographer Manual*: discussion of anamorphic breathing and the
  close-focus widening commonly called anamorphic mumps.
  <https://www.gouastudio.com/amcinman.pdf>
- ARRI Master Anamorphic data sheets: describe correction of the “fat face
  effect” as a lens characteristic.
  <https://www.arri.com/resource/blob/178216/d6fa949dec02494bd9f7e3ee46069aa8/master-anamorhic-data-sheets-data.pdf>
