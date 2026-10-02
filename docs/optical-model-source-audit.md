# Optical blur and chromatic model source audit

This engineering note records the sources considered before replacing Lens
Debaser's field/aperture blur or chromatic approximation. It is not user-guide
copy and it does not imply that third-party code has been incorporated.

## Product constraints

- interactive 1080p/4K grading on Apple Silicon and Metal;
- extended-range, scene-linear optical processing;
- smoothly space-varying field response;
- arbitrary blade count, curvature, aspect, rotation, cat-eye, pupil shift,
  clipping, rim weighting and swirl;
- predictable still-frame output without temporal noise;
- qualitative optical plausibility rather than offline ray tracing.

## Aperture and defocus approaches reviewed

### Retain as design inputs

- NVIDIA, *Practical Post-Process Depth of Field*:
  <https://developer.nvidia.com/gpugems/gpugems3/part-iv-image-effects/chapter-28-practical-post-process-depth-field>
  documents the sample-density/ringing problem in sparse gathers and the value
  of continuous, downsampled blur levels for a responsive approximation.
- NVIDIA, *Depth of Field: A Survey of Techniques*:
  <https://developer.nvidia.com/gpugems/gpugems/part-iv-image-processing/chapter-23-depth-field-survey-techniques>
  provides the useful taxonomy of accumulation, layered, scatter and gather
  methods and their visibility/bleeding trade-offs.
- NVIDIA, *High-Quality Filtering*:
  <https://developer.nvidia.com/gpugems/gpugems/part-iv-image-processing/chapter-24-high-quality-filtering>
  supports combining a small analytic reconstruction filter with hardware
  interpolation instead of representing a large footprint with isolated taps.
- Apple Metal mipmap and multistage-filter guidance:
  <https://developer.apple.com/documentation/metal/generating-mipmap-data>
  and
  <https://developer.apple.com/documentation/metal/implementing-a-multistage-image-filter-using-heaps-and-fences>
  support a reusable prefiltered image pyramid and transient/aliased storage on
  Apple GPUs.
- MetalPetal's MIT-licensed hexagonal bokeh implementation:
  <https://github.com/YuAo/HexagonalBokehBlur> demonstrates an efficient
  separable approximation and is useful as a performance reference.
- OpenDefocus:
  <https://github.com/opendefocus/opendefocus> demonstrates a GPU-accelerated,
  configurable convolution architecture with cat-eye, astigmatism and axial
  aberration. Its EUPL implementation is a validation/reference source, not
  code to import into this project.
- Chaudhury et al., *Fast space-variant elliptical filtering using box
  splines*: <https://arxiv.org/abs/1003.2022> is relevant to constant-cost
  radial/tangential softness, although it cannot reproduce the full pupil.

### Not selected as the primary model

- Full spectral/ray-traced lens simulation is too slow and needs lens
  prescriptions that the plugin intentionally does not require.
- FFT convolution is attractive for very large invariant kernels, but Lens
  Debaser's pupil changes with field position and depth; FFT setup and latency
  are also a poor fit for interactive parameter changes.
- Pure separable polygon/hexagonal bokeh is fast but cannot faithfully retain
  the present arbitrary pupil, rim, clipping, cat-eye and swirl controls.
- Sparse full-resolution Poisson/golden-angle gathers alone do not scale to
  large footprints: sample spacing becomes visible as copies or ringing.
- Temporal stochastic reconstruction is unsuitable for deterministic stills
  and risks shimmer during grading.

## Aperture direction selected for the next experiment

Keep the existing analytic pupil parameterization, but sample it from a
prefiltered source pyramid. Select/blend the source level from each sample's
footprint, then use adaptive low-discrepancy pupil samples plus a small
reconstruction filter. This preserves the engine's distinctive pupil controls
while preventing a large pupil footprint from being reconstructed from sharp,
widely separated source copies. Compare it against the current 96-sample path
at moderate and caricature settings before considering production adoption.

## Adaptive reconstruction experiment result

The inexpensive reconstruction-only variant was evaluated after the improved
field blur and chromatic-ordering candidate. It widened the existing separable
aperture reconstruction according to pupil deformation without adding another
full-frame stage.

Do not adopt this variant. Its GPU timing was effectively neutral on the Apple
M1 test system (about +0.2% for Bokeh Swirl, -0.8% for Petzval, and +0.6% for
the combined chromatic/defocus case), but it produced no useful perceived
improvement. Presets 05, 06, 18, and 19 retained the same extreme-edge
behavior, and the diagnostic impulse energy, RMS radius, and peak were
identical. The images differed at the file/pixel level, but not enough to
alter the visual judgment. Keep the already preferred core field/chromatic
candidate and reject this additional aperture-reconstruction branch.

## Chromatic approaches reviewed

- Jeong et al., *Chromatic Aberration Rendering for a Physically-based Camera*:
  <https://cg.skku.edu/pub/papers/2016-jeong-cgi-chroma-cam.pdf> treats
  dispersion as wavelength-dependent image formation and explicitly addresses
  the lens sampling needed to avoid spatial aliasing.
- Mantiuk et al., *Rendering Algorithms for Aberrated Human Vision
  Simulation*: <https://pmc.ncbi.nlm.nih.gov/articles/PMC10023823/> describes
  chromatic rendering with wavelength-dependent PSFs, commonly represented by
  separate RGB kernels, and spatially varying PSF interpolation.
- Bauer et al., *Fast Two-step Blind Optical Aberration Correction*:
  <https://arxiv.org/abs/2208.00950> models measured lens PSFs with compact RGB
  Gaussian parameters and treats remaining lateral red/green and blue/green
  displacement separately.
- NVIDIA, *Image-Space Gathering*:
  <https://research.nvidia.com/sites/default/files/pubs/2009-08_Image-Space-Gathering/HPG09-ISG.pdf>
  supports importance-sampled spatially varying filtering and smooth filter
  support rather than discrete post-effect replicas.

Stylised RGB-split shaders were rejected as primary references: they displace
sharp display channels and do not model a wavelength-dependent optical PSF.

## Chromatic direction promoted to the production candidate

The former approximation blurred an undispersed image and then added a sharp
triangular RGB residual. That order creates visible zero/half/full-offset
copies. The experimental metallib instead:

1. reconstructs geometry and achromatic field softness;
2. treats that result as the common optical PSF;
3. shifts the red and blue PSF centres with the existing lateral, anamorphic,
   refractive, prism and variation controls;
4. adds a compact centred spectral footprint only for large offsets;
5. passes the chromatically formed image to aperture and scatter stages.

For a locally constant field, convolution and channel-centre displacement
commute, so this two-pass approximation represents separate RGB PSFs without
tripling every field-blur texture lookup. It costs one full-resolution pass and
normally three bilinear reads per pixel. After the isolated visual and timing
comparison was accepted, this core field/chromatic model became the production
candidate. The rejected source-pyramid and adaptive aperture-reconstruction
branches were removed rather than carried into the normal engine.

The promoted production candidate was benchmarked at 1920×1080 on Apple M1.
Neutral measured 1.394 ms GPU, geometry 8.474 ms, combined chromatic/defocus
50.511 ms, Aperture 41.912 ms, Bokeh Swirl 40.983 ms, and Petzval 46.097 ms.
Relative to the recent production runs, the material increases are roughly
1.4–1.6 ms for the heavy field case and about 3 ms for combined chromatic and
defocus processing. Aperture-family timings did not regress in this run. This
absolute cost was accepted for full-library visual validation because the new
model removes clearly visible discrete copies and stair-stepped field blur.

## Required validation after production adoption

If the new field, chromatic and aperture reconstruction is accepted and
deployed as a new engine model, every existing visual example becomes
unvalidated. Re-render the complete demonstration and cinematic preset
library, then review and explicitly pass each preset and its corresponding
visualisations. Give particular scrutiny to presets using shaped aperture,
bokeh, field softness, lateral or longitudinal chromatic aberration,
anamorphic aberration, prism dispersion or combinations of those controls.
Settings tuned against the former sampler may become too strong, too weak or
qualitatively different even when the parameter values have not changed.
Retune presets only after inspecting their new renders; do not carry previous
visual approval forward automatically.
