# Lens Debaser 1.50 processing-model audit

This audit reviews the renderer as a general lens-effects model. Hawk and Cooke
profiles are calibration clients of the model; they do not define its stage
order.

## Runtime stage contract

1. Decode the selected working encoding to scene-linear AP1.
2. Pack the optional second depth input into the internal alpha carrier.
3. Map lens coordinates: radial/moustache/cylindrical distortion, field-gated
   stretch and warp, swirl, refractive irregularity and dispersion.
4. Sample lateral and anamorphic chromatic displacement at the mapped
   coordinate.
5. Reconstruct field-dependent radial/tangential focus loss, astigmatism and
   smear. Chromatic displacement is therefore softened by the field PSF rather
   than pasted over it afterward.
6. Add focus-transition longitudinal chromatic response.
7. Apply signed detail transfer. Positive enhancement is attenuated wherever
   the field PSF is already defocused; negative detail loss remains active.
8. Add source-gated coma, then apply vignette, transmission, variation,
   front-element wear and internal optical-density attenuation.
9. Extract bloom, glare, halo and flare energy from that geometrically aligned
   direct-optics result. The packed depth carrier follows the same mapped
   coordinate as RGB.
10. Reconstruct the spatial aperture/exit-pupil approximation and the reduced
    scatter families. Detect the dominant coherent flare source and evaluate
    diffraction/reflection primitives analytically at full output resolution.
11. Composite direct optics, aperture and additive scatter, apply the global
    Blend once, and encode back to the requested working space.

This order is retained because it provides a coherent image-space
approximation at interactive cost. A full wave/ray-optical simulation would
interleave wavelength-dependent pupil integration and sensor response, but is
not appropriate for this runtime target.

## Changes made by this audit

- Removed the obsolete full-frame highlight output from `ldbOpticsMain`. All
  active scatter families already extract thresholded energy from the aligned
  direct-optics buffer, so the old write and luminance calculation were dead.
- Changed the direct buffer's internal alpha from the unwarped destination
  pixel to the mapped centre sample. Depth-aware aperture and scatter now
  compare geometrically aligned RGB and depth near distortion and peripheral
  warp.
- Replaced the fixed 16x16 dispatch policy with per-pipeline threadgroup sizes
  derived from Metal's `threadExecutionWidth` and
  `maxTotalThreadsPerThreadgroup`. Exact image grids are dispatched with
  `dispatchThreads`.
- Prevented positive Fine Detail, Microcontrast, Sagittal Detail and Tangential
  Detail from rebuilding sharp texture after strong field defocus. Standalone
  controls and negative detail loss retain their established response.

## Control-family review

| Family | Current model basis | Audit decision |
| --- | --- | --- |
| Radial/moustache geometry | Brown-Conrady-style radial powers plus bounded creative field terms | Keep. The conventional polynomial remains recognizable and the nonstandard edge terms are clearly separated. Calibrated real-lens radial mappings must remain monotonic/bijective. |
| Field shape and optical center | Independent elliptical response field and lens-axis center | Keep. Their separation is intentional and covered by independence tests. |
| Lateral/anamorphic CA | Wavelength-channel displacement growing with off-axis field | Keep. It is evaluated before field defocus and softened with that response. |
| Longitudinal CA | Chroma-only near/far focus-transition response | Keep as a perceptual approximation; it remains depth-conditioned when a map is present. |
| Defocus, astigmatism and smear | Compact spatial PSF approximation with radial/tangential axes | Keep. It is faster than a per-pixel FFT/PSF atlas and already covers the required creative range. |
| Aperture, cat eye, pupil shift/clip/rim and bokeh swirl | Sampled exit-pupil footprint with field-dependent deformation | Keep. The exit pupil is expected to shrink and move off axis; current controls expose that behavior without tracing a lens prescription. |
| Detail/MTF | Two compact directional frequency bands | Keep with the corrected defocus interaction. It is a grading-oriented MTF approximation rather than an optical transfer solver. |
| Coma and spherical halo | Source-gated asymmetric tail and depth-aware smooth halo | Keep. Ordinary SDR edges remain protected from shifted-image artifacts. |
| Vignette and image circle | Natural, optical and mechanical factors | Keep. Mechanical coverage remains separately controllable from smooth falloff. |
| Bloom and glare | Thresholded scene-linear separable scatter | Keep. Reduced buffers are radius- and memory-bounded; compact radii retain higher resolution. |
| Anamorphic flare, diffraction and reflections | Hybrid reduced broad scatter plus full-resolution analytic primitives | Keep. It avoids the sampled clusters, striping and stair-stepped gradients found in the retired procedural model. |
| Transmission and coating response | Scene-linear color/density/contrast/highlight mapping | Keep. This is intentionally a finishing approximation, not spectral coating simulation. |
| Refractive irregularity | Smooth low-frequency thickness/index-gradient displacement | Keep. It remains deterministic and field-gated, with optional dispersion. |
| Front-element wear | Restrained transmission/tint masks plus illumination-driven scatter | Keep supported but conservative. It must never become a literal bright scratch overlay. |
| Internal contamination | Continuous domain-warped optical-density field plus bounded scatter | Keep. It models broad internal clouding, not front-surface dust, droplets or fingerprints. |
| Capture/Look macros and Variation | Host-side coordinated parameter mapping | Keep. These modify generic model controls before neutral/active-stage selection and do not introduce preset-specific shader paths. |
| Depth | Optional normalized second input with focus and layer protection | Keep with the corrected mapped carrier. It remains an image-space approximation and cannot reconstruct hidden background geometry. |

## Reference and resource status

The generic model has been checked against the local multi-lens bokeh and test
footage library under `inputs/reference_lenses`, including spherical primes,
vintage primes and multiple anamorphic families. Those assets validate the
range of pupil deformation, cat-eye clipping, swirl, field loss, chromatic
behavior and highlight structure. Only Hawk V-Lite Vintage '74 and Cooke
Anamorphic /i Special Flare currently have compiled, named profile
calibrations. Other factory looks remain creative model-space presets and must
not be described as measured lens replicas.

External technical references used for the general model audit:

- OpenCV camera calibration documents the radial `k1/k2/k3` and tangential
  distortion family and states that real calibrated radial mappings should be
  monotonic and bijective:
  https://docs.opencv.org/5.0/main_modules/calib.html
- PBRT's realistic-camera model describes the field-dependent exit pupil,
  off-axis pupil shrinkage and resulting vignetting that motivate the pupil,
  cat-eye, clipping and vignette controls:
  https://pbr-book.org/3ed-2018/Camera_Models/Realistic_Cameras
- NVIDIA's image-space gathering work describes depth ordering as essential to
  defocus and shows that the spatial weighting function can represent bokeh
  shape, while acknowledging the limitations of an image-space gather:
  https://research.nvidia.com/sites/default/files/pubs/2009-08_Image-Space-Gathering/HPG09-ISG.pdf
- Apple's current Metal guidance recommends sizing compute threadgroups from
  each pipeline's execution width and occupancy limit rather than assuming one
  fixed group geometry:
  https://developer.apple.com/documentation/metal/calculating-threadgroup-and-grid-sizes
- Apple documents optimized Gaussian and pyramid filters in Metal Performance
  Shaders. They remain useful performance references, but adopting texture-only
  MPS kernels would require a larger buffer-to-texture engine rewrite and would
  not preserve Lens Debaser's depth-aware, shaped, extended-range scatter
  semantics:
  https://developer.apple.com/documentation/metalperformanceshaders/image-filters

## Deliberate non-changes

- No ray tracer, FFT PSF atlas, neural model, spectral coating solver or
  per-preset shader branch was added. Those would conflict with interactive
  finishing performance and the model-first preset architecture.
- No generic control was tuned specifically to make Hawk or Cooke pass. Their
  calibrated profiles continue to consume the same engine used by every other
  preset.
- The current buffer pool and bounded reduced-resolution scatter policy remain
  appropriate. MPS, heaps, argument buffers and half precision may be
  reconsidered only after device profiling shows a measured bottleneck; they
  are not automatic improvements for this buffer-based OFX pipeline.

## Validation required

Run the standard engine suite, benchmark, and Visual Pass 78. Review outputs
325-330. The grid/highlight fixture is deliberately split into near and far
depth layers and subjected to strong geometry. Compare depth-free and
depth-aware aperture/scatter outputs at the central layer boundary. Depth-aware
results should suppress cross-layer reconstruction without displaced depth
edges, block artifacts, or a second unwarped halo. Outputs 331-334 compare the
Golden Portrait Prime tiers with their real-footage source; outputs 335-338 use
the ISO chart to verify the centre-to-field progression of the Close-Focus
Macro tiers. Pass 77 is retained as an immutable superseded audit: its scatter
sources did not overlap the depth boundary and its wide scene was not an
appropriate Macro/detail-transfer fixture.
