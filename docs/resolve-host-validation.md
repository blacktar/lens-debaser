# Resolve host-validation checklist

## Open items
- Append the current plugin version to the user-facing effect label everywhere
  it is appropriate, beginning with `Lens Debaser 1.2`. Keep the stable OFX
  identifier `com.ldb.LensDebaser` unchanged so projects continue to resolve the
  plugin across upgrades.
- Confirm the versioned name in Resolve's Open FX menu, effect inspector, plugin
  manager, and any host error messages after every version bump.

## Current host status

- Lens Debaser 1.32 is the current development build and has passed its Resolve
  host check for both native Color-page depth-map input routes.
- Version 1.31 bounds aggregate Metal scatter scratch memory, uses two-buffer
  aperture reconstruction, limits retained scratch memory, and serializes large
  Lens Debaser render graphs per Metal device. Scatter processing now uses one
  fixed high-quality allocation policy, preventing interactive controls from
  changing resource geometry on Resolve's live Metal queue.
- The installed arm64 bundle passes strict code-signature verification.
- Resolve discovers and loads the effect.
- The supplied Lens Debaser icon is displayed in Resolve's Open FX menu.

## Resolve Studio depth validation

### Version 1.32 native Color-page inputs

- `Depth Map Source: Alpha Input` reads the incoming alpha produced by an
  upstream Resolve Depth Map node.
- `Depth Map Source: Second RGB Input` reads grayscale/luminance from the
  optional `Depth Map` image connector exposed by the General OFX context.
- Both paths feed the same normalized engine depth carrier and therefore use
  the existing `Depth Interpretation`, `Depth Near`, `Depth Far`, and
  `Focus Depth` controls.
- Resolve host validation passed for both `Alpha Input` and `Second RGB Input`.
  If a host configuration selects Filter context, `Alpha Input` remains the
  supported route because an optional second image connector is unavailable.

- Resolve Studio's AI Depth Map result can be rendered to a grayscale TIFF and
  packed into the ARRI source alpha with Fusion Channel Booleans.
- With the ARRI RGB connected as Channel Booleans Foreground and the grayscale
  map as Background, RGB is copied from Foreground and Alpha from Background
  Red.
- Lens Debaser reads the packed map with `Depth Map Source: Alpha Input` and
  `Depth Interpretation: Near Black`; `Diagnostic View: Depth Input` matches
  the supplied depth TIFF. `Near White` correctly displays its inverse.
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
