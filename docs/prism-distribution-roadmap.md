# Prism distribution refactor — next build

## Decision

Refactor Prism Refraction in the next build so that prism displacement and
dispersion are independent from the spatial pattern used to apply them. The
current implementation is permanently one-sided because it was authored for a
handheld linear prism entering from one edge. That behaviour remains useful,
but it must become one selectable distribution rather than defining the entire
prism subsystem.

The present prism response only borrows Field Center while ignoring Field
Aspect, Field Rotation, Field Onset and Field Falloff. This prevents centred,
bilateral, radial and uniform prism treatments and makes the current control
group less composable than the other optical responses.

## Required distributions

At minimum, expose these application modes:

- **Uniform:** constant prism response across the frame, with no spatial
  falloff.
- **Linear Edge:** preserve the current one-sided wedge exactly for existing
  presets.
- **Bilateral / Axis:** apply symmetrically from both sides of a selected axis.
- **Radial Field:** derive the local refraction direction from Field Center and
  apply it through the shared elliptical Field envelope.
- **Inverse Field:** strongest around the centre and decreasing toward the
  perimeter, for central optical tools and creative approximations.

The implementation should separate:

1. prism amount, direction and spectral dispersion;
2. distribution shape and direction field;
3. spatial envelope and falloff.

## Control interactions

- Field Center positions radial, inverse-field and elliptical responses.
- Field Aspect controls circular, elliptical and anamorphic coverage.
- Field Rotation rotates elliptical and bilateral distributions.
- Field Onset and Field Falloff control where a shaped response starts and how
  gradually it reaches full strength.
- Prism Direction remains the fixed refraction axis for Uniform, Linear Edge
  and Bilateral modes.
- Prism Edge Bias and Prism Softness apply only to Linear Edge mode.
- Radial Field uses the local direction from Field Center; direction may act as
  a rotation or signed offset if that remains visually useful.

Do not overload the external depth map as a generic mask. If arbitrary masks
are added later, treat them as an explicit effect-mask facility rather than
changing the documented meaning of Depth Input.

## Compatibility and performance

- Existing version-1.57 presets must retain the current Linear Edge result.
- Append new ABI fields; do not reinterpret or reorder released parameters.
- Zero amount must remain strict identity.
- Reuse the existing coordinate-warp stage and avoid an additional render pass.
- Preserve smooth full-resolution envelopes without low-resolution procedural
  clusters, steps or repeated tiles.
- Update Edge Prism Glass and any compound prism presets only after legacy
  equivalence is verified.

## Resolve reference reassessment

After implementation, reassess the supplied Resolve comparison:

- `off.png`: untreated reference;
- `on.png`: completed node-tree result;
- `mask_power_window_and_node_tree.png`: elliptical Power Window and serial
  Lens Blur, Chromatic Aberration Removal and Prism Blur nodes;
- `tilt_shift_blur.png`, `chromatic_aberration_removal.png` and
  `prism_blur.png`: the individual Resolve settings.

The comparison must distinguish source characteristics already present in both
states—especially the horizontal cyan band and black frame—from changes made by
the node tree.

Recreate and compare these visible components independently:

1. the wide elliptical sharp region around the subject;
2. smooth lens-style defocus increasing toward the perimeter;
3. radial red/cyan and blue/cyan edge separation;
4. the centred radial prism-aberration contribution;
5. any residual peripheral smear, geometry or vignette change.

Test both of the following Lens Debaser workflows:

- an entirely internal field-driven version using Field Center, Aspect,
  Rotation, Onset and Falloff;
- a version using the supplied ellipse as the dedicated RGB depth input for the
  defocus component while the new Radial Field prism distribution remains
  internally controlled.

Judge the result on the real image, not only on charts. Record which remaining
differences come from Lens Debaser's red/blue spatial channel model versus
Resolve's independent red/cyan, green/purple and blue/yellow scale and edge
controls. Only then decide whether independent green-channel displacement is
worth adding.

## Validation

- Add isolated tests for every distribution mode.
- Verify shared Field controls affect Radial Field and Inverse Field smoothly.
- Verify Uniform is spatially constant and Linear Edge is backward compatible.
- Check all modes at image boundaries for clamped-pixel streaks.
- Test signed/opposite directions and dispersion at neutral, moderate and
  extreme settings.
- Add a visual pass using the supplied Resolve reference image and suitable
  chart coverage.
- Benchmark the prism cases and confirm the refactor adds no new processing
  stage and no unacceptable regression.
