# Resolve host-validation checklist

## Open items
- Append the current plugin version to the user-facing effect label everywhere
  it is appropriate, beginning with `Lens Debaser 1.2`. Keep the stable OFX
  identifier `com.ldb.LensDebaser` unchanged so projects continue to resolve the
  plugin across upgrades.
- Confirm the versioned name in Resolve's Open FX menu, effect inspector, plugin
  manager, and any host error messages after every version bump.

## Current host status

- Lens Debaser 1.33 is the current development build. Version 1.32 passed its
  Resolve host check for both native Color-page depth-map input routes; the new
  1.33 boundary controls and diagnostics require the next host check.
- Version 1.31 bounds aggregate Metal scatter scratch memory, uses two-buffer
  aperture reconstruction, limits retained scratch memory, and serializes large
  Lens Debaser render graphs per Metal device. Scatter processing now uses one
  fixed high-quality allocation policy, preventing interactive controls from
  changing resource geometry on Resolve's live Metal queue.
- The installed arm64 bundle passes strict code-signature verification.
- Resolve discovers and loads the effect.
- The supplied Lens Debaser icon is displayed in Resolve's Open FX menu.

## Resolve Studio depth validation

### Native Color-page depth input

- Lens Debaser reads luminance from its dedicated optional `Depth Map` RGB
  connector exposed by the General OFX context.
- Resolve's blue key/mask connectors are not used as depth-map inputs.
- `Input Near`, `Input Far`, and `Focus Depth` operate in normalized `0`--`1`
  map space.

### Version 1.33 depth boundary controls

- `Depth Edge Protection` controls how strongly depth-aware aperture and
  scatter reject samples across depth layers.
- `Depth Edge Softness` controls how different two normalized depth values may
  be before they are treated as separate layers. Its default preserves the
  previously approved transition.
- `Diagnostic View: Defocus Amount` displays the response driven by the exact
  current `Focus Depth`, `Defocus Onset`, and `Defocus Falloff` settings.
- `Diagnostic View: Depth Rejection` displays boundaries currently protected
  from cross-layer sampling.
- Visual references 90--94 and the three `v1.33-Test-Depth-Edges-*` presets are
  the acceptance material for this build.

- Lens Debaser reads the map through its dedicated Depth Map connector with
  `Depth Interpretation: Near Black`;
  `Diagnostic View: Depth Input` matches the supplied depth TIFF. `Near White`
  correctly displays its inverse.
- Moving `Focus Depth` from `0` to `1` moves focus through the ARRI still as
  expected. Interaction at 4K is not real-time, but is responsive enough for
  practical adjustment on the tested Apple M1 system.
- With `Aperture Response: 1.000` and `Response Radius: 24.00`, moving
  `Focus Depth` through its complete `0`--`1` range produced acceptable results
  even at the extreme values. No unacceptable boundary bleed, detached halo,
  retained sharp core or hard cutout was observed.
- Depth-aware `Circular`, `Polygon` and `Oval / Anamorphic` aperture shapes
  passed visual inspection on the ARRI frame.
- With aperture and lateral fringing disabled, `Longitudinal Amount: 1.000`
  and `Longitudinal Radius: 7.00` responded correctly while moving
  `Focus Depth` from `0` to `1`; the depth-aware longitudinal CA test passed.
- The same external-depth aperture workflow passed on the supplied iPhone
  Milano frame. Moving `Focus Depth` through `0`--`1` at 4K behaved as
  intended across people and architectural detail. Interaction was not
  real-time but remained responsive enough for practical adjustment.
- A Resolve AI Depth Map TIFF sequence was exported with the clip's input CST
  enabled and the DWG/Intermediate-to-Rec.709 output CST disabled, then packed
  into source alpha in Fusion. `Diagnostic View: Depth Input` played smoothly
  and remained aligned with the moving source.
- Animating `Focus Depth` from `0.000` on the first frame to `1.000` on the
  final frame, with `Aperture Response: 1.000`, `Response Radius: 24.00`,
  `Aperture Shape: Circular` and `Longitudinal Amount: 0.000`, produced smooth
  focus movement without reported flicker or jumps. Playback at 4K was not
  real-time but retained usable interactive responsiveness.
- Lens Debaser 1.26 depth-aware Bloom and Glare passed Resolve inspection with
  the existing alpha-packed depth setup. Compared with `Depth-Free`, `Near
  Black` reduced inappropriate cross-layer scatter while retaining a natural,
  nonzero optical veil around practicals. Boundary references 84--87 showed no
  obvious dark seams, hard depth outlines, missing practicals, retained ghost
  cores or discontinuous halos.
