# Engine ABI v18 — generalized prism distribution

ABI v18 reuses the established 32-bit slot at byte offset 652 as
`prismDistribution`. The constant buffer remains 784 bytes and all subsequent
offsets are unchanged.

Distribution values are:

- `0` Linear Edge — the released v16 one-sided response and compatibility default;
- `1` Uniform — constant coherent displacement across the frame;
- `2` Bilateral / Axis — opposing displacement on both sides of a shaped axis;
- `3` Radial Field — local displacement radiating from the shaped Field Center;
- `4` Inverse Field — fixed-axis displacement concentrated inside the shaped field.

Linear Edge continues to use Prism Edge Bias and Prism Softness. Bilateral,
Radial Field and Inverse Field use Field Center, Aspect, Rotation, Onset and
Falloff. The change remains inside the existing coordinate-warp stage and does
not add a render pass.
