# Lens Debaser engine ABI v16

ABI v16 adds coherent prism refraction without changing the 784-byte Metal
parameter buffer. Five retired ABI v9 front-dirt reserve slots are reused:

- offset 656: `prismAmount`
- offset 660: `prismDirection`
- offset 664: `prismDispersion`
- offset 668: `prismEdgeBias`
- offset 672: `prismSoftness`

Neutral defaults are zero amount and dispersion, 0 degrees direction, 0.65
edge bias and 0.30 softness. A zero amount is bit-neutral and participates in
the engine's neutral bypass.

The base prism displacement is evaluated as one smooth directional wedge in
normalized image coordinates. Red and blue dispersion offsets are derived from
that same displacement around the green base sample, keeping geometry and color
separation spatially coherent.
