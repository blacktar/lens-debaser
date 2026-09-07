# Depth integration roadmap

This document records the evaluated depth architecture for Lens Debaser. The
current explicit alpha-packed workflow remains the stable interchange contract:
depth generators analyse footage, and Lens Debaser consumes the resulting map
deterministically while rendering optical effects.

## Architecture decision

Do not run neural depth inference inside an OFX render callback. Resolve may
request frames concurrently, repeatedly, or out of timeline order. Synchronous
model inference there would combine unpredictable latency, large transient
memory use, model warm-up and temporal-state invalidation with the image effect
that must remain stable. It would also make the same grade depend on an opaque
cache rather than only its media, map and parameters.

Use three interoperable routes instead:

1. **Resolve Studio analysis:** generate depth with Resolve's Neural Engine and
   hand a normalized map to Lens Debaser through source alpha.
2. **External temporal analysis:** generate and cache an image sequence with a
   video model, then use exactly the same alpha carrier.
3. **Depth-Free:** retain Lens Debaser's existing image/field approximation when
   no map is supplied.

The current `Depth Interpretation` choices already cover the useful interchange
families: `Near White`, `Near Black`, `Linear Camera Z`,
`Inverse Z / Disparity`, and `Logarithmic Z`. They should not be replaced by
generator-specific names. Generator setup belongs in documentation or an
upstream helper; interpretation remains a property of the supplied values.

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

### Evaluation result

Video Depth Anything is the best candidate for an optional offline temporal
generator because it is designed for consistent arbitrary-length video rather
than isolated frames. Only the Small model is suitable for ordinary commercial
redistribution without a separate licence: Small is Apache-2.0, whereas Base
and Large are CC-BY-NC-4.0. The reference implementation is a PyTorch analysis
pipeline, not a component suitable for direct OFX rendering.

The proposed implementation is a separate **Lens Debaser Depth Analyse** tool:

- analyse one shot at a time and reset temporal state at cuts;
- run the Small model at its intended analysis resolution rather than at 4K;
- cache a half-float grayscale OpenEXR sequence plus a plain-text manifest;
- record source identity, frame range, model/version, polarity, normalization,
  crop and analysis resolution so stale caches can be detected;
- preserve a stable per-shot scale/offset instead of normalizing every frame;
- optionally emit confidence/edge information later;
- never make this helper a requirement for using the OFX plugin.

Depth Anything V2 Small has an official Apple Core ML package and is useful for
testing an Apple-native single-frame route. It is not a substitute for temporal
video depth: independent frame inference can flicker or pump. It is therefore a
candidate for stills, previews, or a later cached workflow with explicit
temporal stabilization, not the preferred moving-image generator.

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

### Evaluation result

Resolve 21 CineFocus documents both an AI-generated `Internal` depth source and
`From Alpha Input`. Its documented convention is brighter for nearer subjects
and darker for farther subjects, which maps to Lens Debaser's existing
`Near White` interpretation. CineFocus also exposes map limits, gamma,
post-filtering, expansion/contraction and blur. Those are useful upstream map
conditioning operations, but its internal AI map is not documented as a public
third-party OFX input or API.

The next host-validation task is therefore deliberately narrow: determine
whether Resolve FX Depth Map or CineFocus can output its generated map as a
full-range floating-point image/alpha channel downstream. If it can, package a
Fusion `.setting` helper that combines source RGB with generated depth in alpha.
If it cannot, the supported Resolve-native route is to render/cache the depth
sequence first, as already proven with TIFF sequences.

For `CineFocus: From Alpha Input`, set its layer separation to zero when using
an externally supplied continuous map; Resolve documents this as the setting
for an external depth input.

## Map interchange and conditioning

Prefer half-float OpenEXR for new cached depth sequences. It preserves smooth
gradients and values outside a prematurely clipped integer range, has explicit
linear numeric semantics, and is less ambiguous than display-referred TIFF.
TIFF remains supported and has already passed host testing.

Condition maps once upstream where possible. Lens Debaser should add only
controls that are needed for repeatable optical interpretation:

- normalized near and far rails (already implemented as `Depth Near` and
  `Depth Far`);
- normalized focus plane (already implemented as `Focus Depth`);
- a small map-edge softness control for quantized/noisy maps;
- an edge-rejection control that trades foreground protection against holes;
- diagnostics for normalized depth, defocus amount and rejected samples.

Do not duplicate an entire depth-map grading tool inside Lens Debaser. Large
repairs, roto, temporal stabilization, gamma shaping and layer separation are
better performed by the generator or Resolve upstream.

## Implementation phases

### Phase A — current plugin

Version 1.32 adds two native Color-page ingestion routes: upstream alpha and an
optional second RGB depth image. Both are deliberately independent of Fusion.
The second image is converted to a grayscale depth carrier using luminance while
the primary image remains the RGB source.

1. Validate `Alpha Input` and `Second RGB Input` with Resolve FX Depth Map.
2. Add `Depth Edge Softness` and `Depth Edge Protection` under `Depth Input`.
3. Keep their neutral defaults bit-exact with the approved current output.
4. Add `Defocus Amount` and `Depth Rejection` diagnostic views.
5. Extend hard-boundary tests 79--89 for both controls and diagnostics.
6. Supply versioned understated/mid/max test presets where static values apply.

### Phase B — Resolve-native host validation

1. Test the native AI depth effect on ordinary 2D footage.
2. Test whether its raw map can be routed downstream without display encoding.
3. Verify polarity, precision, alpha premultiplication, retimes, cuts and cache
   reuse on Apple Silicon.
4. Package a Fusion helper only if the route is supported and reliable.

### Phase C — optional offline analyser

Prototype Video Depth Anything Small outside Resolve, initially as a command
line/helper application. Validate temporal stability and cache interchange
before considering UI integration or distribution.

Primary references:

- DaVinci Resolve 21 New Features Guide, CineFocus and Depth Map sections
- Blackmagic Design DaVinci Resolve Studio feature documentation

## Candidate future depth-aware effects

Prioritize only effects that gain a meaningful, controllable visual advantage:

1. aperture/defocus radius and focus pulls;
2. longitudinal chromatic aberration near/far assignment;
3. depth-aware bloom and veiling-glare occlusion (implemented in 1.26);
   atmospheric scatter remains future work;
4. depth-conditioned spherical aberration and highlight bokeh (implemented in
   1.27 through the existing Spherical Halo and Aperture controls);
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
