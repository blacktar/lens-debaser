# Output framing and crop roadmap

Future builds should evaluate an **Output Framing / Crop** control group for
effects that displace, blur or spread image content beyond the usable frame.
Examples include geometric distortion, prism displacement, large aperture
reconstruction, Cat-Eye and swirl responses, flare/scatter reach, and other
responses that can reveal clamped borders or reduce the clean image area.

## Manual controls to evaluate

- a predictable uniform overscan/zoom control;
- optional independent horizontal and vertical framing where anamorphic or
  strongly directional effects require it;
- crop/reposition controls that operate after optical processing, without
  changing the optical centre or the field model;
- a clear distinction between hiding unavailable boundary pixels and merely
  enlarging an effect that legitimately spreads across objects inside the
  image;
- interpolation quality, alpha behavior and additional processing cost.

The control group should not silently crop the image at neutral settings. A
manual value must remain stable across frames and be suitable for timeline-
level use.

## Auto Crop feasibility

Evaluate an explicit **Auto Crop On/Off** option, but do not assume it is
appropriate until the following are validated:

- derive the smallest safe crop from active displacement and reconstruction
  bounds rather than analysing picture content;
- include distortion, prism direction/distribution, pupil radius/aspect,
  field shape and other spatially expanding controls in that bound;
- avoid temporal pumping when controls are animated;
- define conservative behavior for procedural variation and effects whose
  energy may legitimately extend outside the source frame;
- decide whether the crop should be calculated per frame, per parameter state,
  or held at a user-approved maximum;
- expose the calculated crop/scale so the user can understand and override it;
- benchmark the feature and reject any design that adds meaningful cost while
  disabled.

Auto Crop should be opt-in and deterministic. If a trustworthy safe bound
cannot be calculated for a particular combination, the UI should retain the
manual crop rather than making a content-dependent guess.

## Validation requirements

Use grids and real footage with important detail touching all four borders.
Test barrel and pincushion distortion, generalized prism modes, maximum
aperture radius/swirl/aspect, directional flare and compound presets. Compare
manual and automatic framing for border repetition, black reveals, excessive
loss of field of view, aspect changes, temporal instability and performance.
