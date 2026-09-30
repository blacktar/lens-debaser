# Preset layering roadmap

## Goal

Evaluate separating the preset library into two user-facing classes:

1. **Full Lens presets** set a coordinated, complete lens character and remain
   suitable as the first preset loaded on a node.
2. **Component presets** change only one defined optical subsystem, allowing a
   user to layer characteristics such as Decentered Dream Glass with a Hawk-like
   anamorphic flare and bokeh treatment without resetting unrelated controls.

This is a useful direction for Lens Debaser. It exposes the engine as a set of
composable optical responses while retaining complete, authored lenses for fast
starting points. It should not be implemented by simply loading today's complete
presets successively: both presets may own field, pupil, chromatic, transmission
and highlight controls, so the second load currently has ambiguous replacement
semantics.

## Recommended model

Presets should explicitly declare their application mode and owned controls.

- `replace` resets the lens controls to neutral and applies a complete Full Lens
  preset. Processing settings such as working space and diagnostics remain
  untouched, as they do now.
- `merge` changes only the keys serialized by a Component preset. Every other
  current control value is preserved.
- Component presets must carry an explicit subsystem/category identifier and a
  stable list or mask of the controls they own. Omitted controls must mean
  **preserve**, never silently reset to neutral.

The UI should make the distinction visible before application, for example:

- `Full Lenses / Decentered Dream Glass / Medium`
- `Components / Anamorphic / Hawk-inspired Flare`
- `Components / Pupil & Bokeh / Vintage 2x Oval`
- `Components / Transmission / Warm Uncoated Glass`
- `Components / Degradation / Internal Haze`

## Composition and conflicts

Component presets should be deliberately narrow. A Hawk-inspired anamorphic
component could own anamorphic distortion, aberration, aperture aspect, flare,
diffraction and reflection controls, while preserving the Dream Glass field
center, refractive irregularity, transmission and other authored traits.

When two components own the same control, the most recently applied component
should win for that control. The host should show the applied component stack or
at least the last applied component per category so the result remains
understandable and reversible. A later Full Lens preset intentionally replaces
the assembled lens character.

Do not add hidden preset-specific renderer branches. Both Full Lens and
Component presets must continue to select operating points in the same top-level
processing model.

## Implementation requirements

- Version the preset schema while retaining compatibility with existing
  `.ldbpreset` files, which should continue to load as Full Lens/replace presets.
- Add preset metadata for application mode, category, display name, version and
  owned controls.
- Preserve a one-step undo for each preset application.
- Provide a clear way to reset one component category without clearing the
  entire lens.
- Prevent duplicate or contradictory serialization of processing-only settings.
- Keep preset application deterministic across Resolve sessions and builds.
- Update the guide to explain replacement versus layering before shipping the
  feature.

## Next-build installer migration

Before installing a new factory preset library, the installer must move the
existing Lens Debaser-managed factory folders (`Demonstrations` and
`Cinematic Lenses`) into a timestamped legacy archive under the Lens Debaser
preset directory. It must then install clean copies of the factory folders from
the current release.

Only factory presets supplied and managed by Lens Debaser may be archived.
User-created presets, user-created folders, renamed or separately stored preset
files, and any other content in the preset directory must remain untouched. The
installer should report the archive location and must avoid merging obsolete
factory files into the current library.

## Validation before adoption

Test at least these combinations on charts and real footage:

- Dream Glass + Hawk-inspired anamorphic component;
- clean base + pupil/bokeh component + transmission component;
- vintage full lens + degradation component;
- two components that intentionally overlap, confirming last-applied ownership;
- removal/reset of one component without changing unrelated controls;
- legacy preset loading and round-trip saving;
- performance parity, since preset composition should not add a rendering stage
  by itself.

The feature is worthwhile if it remains predictable and legible to a colorist.
If ownership cannot be made explicit in the host UI, keep complete lens presets
and offer carefully scoped control-group presets without presenting them as a
general arbitrary stack.

Candidate complete-lens combinations that can be prototyped before component
layering is implemented are evaluated in `compound-preset-roadmap.md`.
