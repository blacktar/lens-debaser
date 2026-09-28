# Lens Debaser engine ABI v5

Version 1.36 appends `apertureBokehSwirl` to `LDBOpticsParameters`. Existing
fields retain their ABI v4 offsets; the structure grows from 560 to 576 bytes.

`apertureBokehSwirl` uses a creative range from 0 to 6:

- `0` retains the established uniform aperture reconstruction.
- `1` produces a clearly visible tangential off-axis footprint; values through
  `6` provide deliberately extreme creative character.
- Increasing values retain a reduced ordinary pupil response in the centre and
  blend toward the full aperture contribution through the Field Shape envelope.
- The same response progressively compresses the pupil radially and extends it
  tangentially around Field Center.
- Field Aspect and Field Rotation shape that spatial response. Field Onset is
  where it begins and Field Falloff is the transition width, so every control
  ordering remains continuous and cannot collapse into a hard ring.
- External depth remains multiplicative: samples on Focus Depth stay sharp and
  spatial bokeh character appears only where defocus exists.

This is a fast perceptual model for characteristic off-axis bokeh, not a
physical ray-traced lens simulation.
