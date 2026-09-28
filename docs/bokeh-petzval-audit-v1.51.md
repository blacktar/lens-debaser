# Lens Debaser 1.51 bokeh and Petzval audit

## Outcome

The aperture architecture remains appropriate for the current quality target:
full-resolution reconstruction, a deterministic 96-sample filled pupil, and
three reconstruction passes. Lower-resolution processing would be faster, but
would reintroduce the pixelated and stair-stepped boundaries previously rejected
during visual review. No additional pass or sample count is introduced in 1.51.

## Build 1.52 follow-up

Pass 79 confirmed that the Petzval field-curvature progression was smooth, but
its point-source fixtures were not valid filled-pupil tests: their partial
Aperture Response deliberately retained 22--45 percent of the direct source.
The combined Cat-Eye and Bokeh Swirl response could also still produce overly
thin curved capsules at strong settings.

Build 1.52 keeps the same 96-sample reconstruction and pass count, but bounds
the combined deformation more conservatively so strong pupils retain radial
area. Pass 80 uses Aperture Response 1.0 and a shorter field transition for all
point-source comparisons. This isolates pupil reconstruction from blend amount;
the already-approved Pass 79 ISO field sequence is not redundantly repeated.

Two correctness problems were found and corrected:

- Pupil Aspect was evaluated only for `Oval / Anamorphic`. It was silently inert
  for polygonal pupils, including the Petzval family. Aspect is now independent
  of pupil outline.
- Bokeh Swirl previously scaled linearly to an approximately 6.7x tangential by
  0.05x radial footprint at the top of its range. That was too thin and broad
  for a filled 96-sample reconstruction. The full 0..6 UI range now follows a
  bounded rational response and remains a filled rotating pupil.

## Model roles

- **Field Curvature** supplies the curved off-axis focal surface.
- **Corner Detail Loss, Astigmatism and Tangential Smear** describe the field
  transfer around that surface.
- **Aperture Response and Radius** establish the defocus footprint.
- **Cat-Eye, Pupil Aspect and Bokeh Swirl** shape and rotate the off-axis pupil.
- **Field Center, Onset and Falloff** protect and position the central subject
  island and control the gradual transition.

Image-structure `Swirl` is deliberately not required for Petzval bokeh. It bends
the sampled image field and remains a separate creative control; Bokeh Swirl
rotates pupil footprints without twisting scene geometry.

## Preset and validation policy

Build 151 adds isolated `Bokeh Swirl` and `Petzval` smoke tiers and two focused
educational presets. The Petzval cinematic family now uses only mild fixed pupil
aspect; most oval character develops from field-dependent Cat-Eye and Bokeh
Swirl instead of a globally squeezed aperture.

Visual Pass 79 uses two appropriate sources:

- isolated point highlights for pupil fill, orientation, continuity and the
  conservative/medium/extreme Bokeh Swirl progression;
- the ISO resolution chart for the protected centre, gradual curved focus and
  conservative/medium/extreme Petzval field progression.

Real portraits with peripheral practicals remain the final Resolve review
source. A point chart alone cannot judge whether the subject island feels
photographically useful, and a resolution chart alone cannot judge pupil shape.
