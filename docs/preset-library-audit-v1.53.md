# Preset library audit — build 1.53

Build 1.53 revises the factory library around the current processing model. It
does not make presets drive the renderer: the renderer remains the source of
optical behavior, while presets select useful operating points in that model.

## Kept

- Existing general-purpose lens families whose behavior still maps cleanly to
  the current controls.
- The reference-calibrated Hawk V-Lite Vintage '74 and Cooke Anamorphic /i
  Special Flare families. Their profile-compiler values are unchanged.
- The three-strength Subtle / Medium / Caricature convention. Medium remains
  the intended starting point; Caricature is both a diagnostic and a creative
  extreme.

## Rebalanced

- Rotating Bokeh Portrait, Petzval Oval Portrait, Bubble Bokeh Triplet,
  Nocturnal Cat-Eye, Close-Focus Macro and Improvised Projector Lens now use the
  corrected filled-pupil and bounded-swirl behavior introduced in build 1.52.
- The aperture, bokeh-swirl and Petzval demonstrations now use full pupil
  reconstruction and the current gradual field envelope.

## Added

- Four single-purpose demonstrations for structured anamorphic flare,
  diffraction rays, pupil decenter/clipping and bubble-rim energy.
- Decentered Dream Glass, a compound seven-blade portrait optic combining a
  displaced focus island, asymmetric pupil clipping, warm transmission,
  chromatic asymmetry and controlled rim energy.
- Prismatic Night Scope, a compound 1.8x anamorphic treatment combining a
  layered streak, decaying reflection train, vertical diffraction, cool glare,
  oval bokeh and restrained aberration.

## Visual gate

Pass 81 deliberately uses different sources for different questions:

- a compact bright source on a dark photographed frame for analytic flare,
  reflection-train and diffraction behavior;
- a regular isolated-point field for pupil shift, clipping and rim shape;
- photographed texture for the compound Decentered Dream Glass family.

This avoids judging pupil reconstruction on a resolution chart or judging
flare structure on footage without a suitable compact highlight.

## Build 1.54 correction

Pass 81 showed that Prismatic Night Scope exposed its analytic primitives too
literally: saturated capsule ghosts, detached bands and a vertical ray read as
overlays instead of one optical event. Its Medium and Caricature variants were
re-authored with restrained larger ghosts, a cooler unified tint, broader
source-linked glare and stretched bloom, and a monotonic increase in total
energy. The same correction pass strengthens the decentered-pupil educational
example and restores filled energy beneath the bubble rim.

## Build 1.55 review outcome

Pass 82 fixed the Night Scope strength inversion but confirmed that the family
still lacked a convincing reference-grounded optical identity. It was removed
rather than shipped as a catalogue filler. Bubble Rim and Bubble Bokeh Triplet
were reduced to a supporting rim over a visibly filled pupil; Pass 83 compares
that result directly with the same pupil reconstruction at zero rim weight.
