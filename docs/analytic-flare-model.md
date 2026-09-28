# Analytic flare model

Lens Debaser uses a hybrid flare model intended for responsive finishing work,
not per-frame scientific lens tracing.

The established reduced-resolution scatter path remains responsible for broad
horizontal streak energy and veiling wash. A deterministic GPU reduction then
finds at most four coherent highlight sources. Candidates must be local maxima,
are spatially suppressed, and secondary sources must retain a meaningful share
of the dominant source energy.

Thin shaped elements are evaluated analytically at full output resolution:

- vertical diffraction uses a narrow exponential core plus a broader soft tail;
- the internal reflection is a filled ellipse with a restrained rim and core;
- ghost position follows the dominant source around Optical Center;
- the photographed scene is never copied or reprojected into a ghost;
- only the dominant source owns a ghost path, preventing practical-light arrays
  from forming tiled colored clusters.

Factory lens presets act as compact lens profiles. They coordinate broad
scatter, analytic reflection position and scale, coating color, diffraction,
aperture response and the existing imaging-character controls. More expensive
ray tracing and PSF tools remain offline calibration references rather than
runtime dependencies.

## Processing order

1. Decode to linear AP1.
2. Apply geometry, chromatic, field and transmission behavior.
3. Extract and downsample eligible highlight energy.
4. Reconstruct broad scatter in the reduced buffer.
5. Detect coherent flare sources.
6. Reconstruct analytic shaped elements at full resolution during composition.
7. Encode to the selected working space.
