# Engine ABI v15 — general pupil and internal-cloud model

ABI v15 converts previously reserved fields into general-purpose optical
controls while retaining the 784-byte parameter-buffer layout.

The pupil model adds `aperturePupilShift`, `aperturePupilClip`, and
`apertureRimWeight`. These independently control off-axis pupil displacement,
lens-barrel clipping, and the distribution of energy between the pupil centre
and rim. They operate after the existing blade/oval construction and before
the field-dependent cat-eye and swirl mapping.

The internal-contamination model adds `internalDirtSoftness` and
`internalDirtComplexity`. The contamination mask is now a normalized,
multi-scale optical-density field assembled from smooth deterministic lobes.
It contains no image-plane particles or temporal noise. Existing amount,
scale, smear, scatter, and seed controls remain independent.

Processing order is explicit: contamination density modifies the direct optical
image before aperture reconstruction; contamination-driven highlight energy is
then redistributed once by the same downsampled separable scatter graph used by
bloom. The destination-space contamination mask gates that smooth scatter during
composition. No wide sparse kernel remains in the direct stage.

All new controls are neutral at zero. The default cloud softness and complexity
are 0.5 for new instances; saved v14 parameter buffers remain structurally
compatible and resolve their formerly reserved values to zero.
