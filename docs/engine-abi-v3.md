# LDB Optics engine ABI version 3

ABI version 3 appends a neutral-by-default perceptual longitudinal chromatic
aberration model. All version-1 and version-2 fields retain their offsets.

In Depth-Free mode the model uses local focus transitions rather than scene
depth: the sharp side receives the selectable near-focus chroma and the
surrounding defocus side receives the selectable far-focus chroma. This remains
a fast visual approximation suitable for grading, not a physical reconstruction.

## Neutral state

- Longitudinal Amount: `0.0`
- Longitudinal Radius: `4.0` pixels
- Near-Focus Color: magenta-biased (`1.0, 0.35, 0.75`)
- Far-Focus Color: green-biased (`0.35, 1.0, 0.65`)

Existing `.ldbpreset` files load these neutral/default values. New presets store
the amount, radius, and both colors as plain text.

Version 1.18 appends the first host-validation depth fields: interpretation,
source channel, and raw near/far normalization. Resolve does not expose arbitrary
OFX auxiliary clips in the tested Fusion wrapper, and its blue Effect Mask input
is not semantically a depth input. External depth is therefore packed upstream
into the incoming image alpha channel and inspected using the depth diagnostic.
The plugin restores opaque output alpha while packed-alpha depth is active. Depth
was initially diagnostic-only so transport and normalization could be validated
inside Resolve before affecting the picture.

Version 1.19 uses the validated normalized depth to drive longitudinal chromatic
aberration. `Focus Depth` selects the normalized in-focus plane. Signed distance
from that plane selects the near- or far-focus color and smoothly increases the
effect away from focus. Depth-Free mode ignores Focus Depth and retains the
approved image-derived result. Other optical families remain depth-free until
their occlusion and transition behaviour is separately validated.

Version 1.20 broadens the longitudinal response with a two-band edge envelope,
balances near/far depth tinting, lowers small-feature suppression, and increases
normal-view creative gain. The tint vectors remain AP1-luminance normalized and
lateral red/blue fringing remains an entirely independent model.

Version 1.21 applies the same normalized Focus Depth plane to Aperture Response.
External-depth modes keep that plane sharp and smoothly increase the existing
continuous aperture-shaped defocus with depth distance. Depth-Free mode retains
the original full-frame aperture approximation.

Version 1.22 moves external-depth modulation into the aperture footprint radius
instead of crossfading a sharp source with a fixed maximum-radius footprint.
This removes retained point cores and produces one continuous pupil footprint
whose size grows with distance from Focus Depth.

Version 1.23 retains the validated 96-sample aperture footprint and its two
reconstruction passes. It removes redundant per-pixel pupil trigonometry and
softness exponentials through equivalent recurrences, and replaces bilinear
sampling at integer reconstruction taps with direct bounded pixel reads.

Version 1.24 makes externally depth-driven aperture sampling bilateral across
hard layer boundaries. Pupil and reconstruction samples are weighted by depth
agreement, while each pass preserves the target depth carrier. This suppresses
foreground/background contamination without changing Depth-Free rendering.

Version 1.25 makes that protection occlusion-directed: farther layers cannot
bleed forward, focused foreground remains crisp, and defocused nearer layers
may expand over farther targets in proportion to their own defocus. This avoids
the unnaturally sharp cutout boundary produced by fully symmetric rejection.

Version 1.26 applies the same explicit depth interpretation automatically to
Bloom and Glare. A nearer target strongly attenuates scattered light from
farther samples, while light originating on a nearer layer may veil a farther
target. A restrained nonzero optical floor reflects that lens scatter occurs
after scene occlusion and prevents distant practicals from being cut out.
Depth-Free rendering and the existing Bloom and Glare controls retain their
previous behavior; no additional UI control is required.

Version 1.27 depth-conditions the existing Spherical Halo response. With an
external depth interpretation active, highlight eligibility rises smoothly
with distance from `Focus Depth`; highlights on the focus plane remain clean,
and near/far defocused highlights receive the established spherical-aberration
shape. The scatter also uses the softened layer protection introduced for
Bloom and Glare. `Depth-Free` preserves the 1.26 response and no new parameter
is added.
