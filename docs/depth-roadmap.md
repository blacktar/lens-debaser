# Depth integration roadmap

This is deferred research for future Lens Debaser versions. It must not delay
validation of the current explicit alpha-packed depth workflow.

## Video Depth Anything

Evaluate Video Depth Anything (CVPR 2025) as an optional temporal monocular
depth generator. The project is based on Depth Anything V2 and targets long
videos, temporal consistency, generalization, and arbitrary sequence length.

Research before implementation:

- model and dependency licences, including redistribution constraints;
- Apple Silicon execution paths (Core ML, Metal/MPS, or an external helper);
- memory, latency, warm-up, and practical 1080p/4K throughput;
- temporal stability across cuts, occlusions, motion blur, rack focus, grain,
  flashes, and exposure changes;
- relative-depth scale/shift normalization and shot-boundary resets;
- offline analysis/cache versus live OFX inference;
- deterministic cache format, invalidation, and interchange through float alpha
  or an auxiliary rendered file;
- whether confidence or uncertainty maps can prevent depth-edge artefacts.

Project: https://videodepthanything.github.io/

## DaVinci Resolve Studio native depth

Evaluate Resolve Studio's native AI Neural Engine analysis as a first-class
depth generator, not merely as a way to route an existing map. This includes
the Resolve FX Depth Map analysis of ordinary 2D footage and Resolve 21
CineFocus with `Source: Internal`, where Resolve's AI estimates which parts of
the 2D image are nearer or farther from the camera. Also test CineFocus
`From Alpha Input` as the complementary external-map route. Its normalized
Focus Distance, depth-of-field, inversion, near/far limits, and gamma controls
closely match Lens Debaser's current alpha carrier and normalized Focus Depth.

Research and host validation:

- exact Color-page and Fusion-page node graphs for exporting native depth into
  Lens Debaser's incoming alpha without sacrificing the source RGB;
- Resolve Neural Engine analysis setup for stills and moving footage, including
  analysis initiation, tracking/temporal behaviour, re-analysis, and cache reuse;
- whether the standalone Resolve FX Depth Map or CineFocus Internal result can
  be emitted as a full-range floating-point grayscale/alpha map for downstream
  third-party OFX processing;
- comparison of the native AI result before and after its Near Limit, Far Limit,
  Gamma, Invert, and quality controls, establishing which stage should feed us;
- `Use OFX Alpha`, alpha premultiplication, caching, render order, and whether
  the native map can remain floating point through the chain;
- map polarity and numeric range for Depth Map and CineFocus;
- temporal stability and quality/performance modes on Apple Silicon;
- behaviour at mattes, blanking, letterbox edges, transparency, cuts, and
  retimed clips;
- whether Resolve exposes any supported API beyond node/alpha composition;
- interoperability presets for Near White/Near Black, limits, and gamma;
- side-by-side evaluation against Video Depth Anything on the same footage.

Test material should include people, architecture, fine foreground occluders,
transparent and reflective objects, shallow-focus footage, textureless walls,
fast motion, camera motion, cuts, grain/noise, letterboxing, and real focus
pulls. Record temporal flicker, edge tearing, depth reversals, resolution,
analysis time, playback cost, and Apple Silicon memory use.

The plugin must not depend on undocumented access to Resolve's proprietary
internal depth analysis. The practical supported route remains an explicit map
provided through the image alpha channel unless host testing proves otherwise.

Primary references:

- DaVinci Resolve 21 New Features Guide, CineFocus and Depth Map sections
- Blackmagic Design DaVinci Resolve Studio feature documentation

## Candidate future depth-aware effects

Prioritize only effects that gain a meaningful, controllable visual advantage:

1. aperture/defocus radius and focus pulls;
2. longitudinal chromatic aberration near/far assignment;
3. depth-aware bloom, veiling glare, and atmospheric scatter occlusion;
4. depth-conditioned spherical aberration and highlight bokeh;
5. foreground/background-specific optical character;
6. optional depth-edge protection and confidence-aware blending.

Geometry distortion, lateral chromatic aberration, vignette, transmission,
sensor-independent MTF character, and most off-axis field effects should remain
primarily image/field based unless a concrete photographic benefit is shown.
## Hard-boundary validation

Visual validation images 79--83 use a packed-alpha discontinuous depth scene
with a curved foreground silhouette, hair-like strands, thin railings, crossing
edges and bright practicals adjacent to depth jumps. They compare the source and
normalized map with near-, railing- and far-focused aperture renders. These are
the acceptance references for boundary bleeding and eventual occlusion-aware
sampling; smooth gradients alone are not sufficient validation.
