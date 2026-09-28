# Lens Debaser engine ABI v7

ABI v7 appends 32 bytes to `LDBOpticsParameters` for a deterministic refractive
irregularity prototype. All v6 and earlier offsets remain unchanged; the
structure grows from 608 to 640 bytes.

The new controls are Irregularity Amount, Irregularity Scale, Edge Bias,
Directionality, Direction, Irregular Dispersion, and Irregularity Seed.

The implementation runs inside the existing direct-optics Metal kernel. It
uses a compact analytic vector field, adds no render pass or intermediate
texture, and reuses its displacement vector for wavelength separation. Neutral
amount bypasses the field and preserves the prior image.
