# Resolve test presets

These deliberately incomplete `.ldbpreset` files rely on Lens Debaser's neutral
defaults for every omitted value. Load any one file through the plugin's Load
button; every preset in this folder should then appear once in the Preset menu.

Each static test has three strengths:

- `Understated` verifies that the intended responses begin cleanly.
- `Mid` exposes their balance at useful visible strength.
- `Max` stresses the response for clipping, ghosting, edge streaks and other
  unwanted artifacts. It is intentionally not a tasteful production setting.

Processing settings are deliberately absent: Input Working Space and Diagnostic
View are host/session context and must neither be loaded
from a preset nor change its selected status. These files are versioned test
fixtures, not factory looks.

## Version 1.69 active smoke tests

Only `v1.69-` fixtures remain in the active tests folder. Earlier build
fixtures are retained under `presets/archive/`.

For bokeh shape, use the isolated point-highlight aperture chart:

- `v1.69-Smoke-Bokeh-Swirl-Conservative.ldbpreset`
- `v1.69-Smoke-Bokeh-Swirl-Medium.ldbpreset`
- `v1.69-Smoke-Bokeh-Swirl-Extreme.ldbpreset`

For Petzval behavior, use both a portrait or textured central subject with
peripheral practicals and the ISO chart:

- `v1.69-Smoke-Petzval-Conservative.ldbpreset`
- `v1.69-Smoke-Petzval-Medium.ldbpreset`
- `v1.69-Smoke-Petzval-Extreme.ldbpreset`

The point chart judges pupil fill, orientation and smooth field progression.
The ISO chart judges curved focus and centre protection. Real footage is needed
to judge whether the resulting subject island feels photographically useful.

The active folder also contains focused 1.69 fixtures for prism distribution,
pupil shift, clipping and rim weighting, cloud response, and both Resolve Edge
FX routes. The filenames currently present in `presets/tests/` are the
authoritative active inventory; do not copy old versioned fixtures back into it.

## Version 1.41 ABI v15 smoke-test history

Five isolated Resolve fixtures enable the required parent processing and make
each new control visible:

- `v1.41-Smoke-Pupil-Shift.ldbpreset` — radial off-axis pupil displacement.
- `v1.41-Smoke-Pupil-Clipping.ldbpreset` — gradual asymmetric barrel clipping.
- `v1.41-Smoke-Pupil-Rim-Weight.ldbpreset` — centre-to-rim energy transfer.
- `v1.41-Smoke-Cloud-Softness.ldbpreset` — continuous density-edge softness.
- `v1.41-Smoke-Cloud-Complexity.ldbpreset` — multiscale modulation of the broad cloud field.

Use isolated defocused points for the pupil fixtures. Use real footage with
bright windows or practicals for the cloud fixtures. The expected result is
recorded in each preset comment.

Version 1.36 uses only the verified dedicated RGB Depth Map connector. Resolve's
blue key/mask inputs are not depth sources.

Version 1.36 adds spatially varying aperture response. These fixtures keep the
centre usable while progressively shaping peripheral bokeh through the Field
Shape controls:

- `v1.36-Test-Bokeh-Swirl-Understated.ldbpreset`
- `v1.36-Test-Bokeh-Swirl-Mid.ldbpreset`
- `v1.36-Test-Bokeh-Swirl-Max.ldbpreset`

Version 1.33 adds three boundary-conditioning fixtures. Use the same native
depth input for all three and compare foreground/background contamination:

- `v1.33-Test-Depth-Edges-Understated.ldbpreset`
- `v1.33-Test-Depth-Edges-Mid.ldbpreset`
- `v1.33-Test-Depth-Edges-Max.ldbpreset`

## Separate projection candidate examples (not active release fixtures)

Six test examples are in `presets/experiments/projection-resolve-candidate/`, outside this active test folder and the published 1.69 factory collection. They target “Lens Debaser Projection Test” only: equidistant/stereographic at 20%, 45%, 70% Amount, 55° half-diagonal Field Angle and Balanced framing. They are not promoted factory presets and are not part of the public 1.69 authoring schema. Candidate preset round-trip and edited-state behavior passed focused user Resolve review on 2026-10-05.

The isolated projection host-test sequence passed the focused user checks on 2026-10-05 (motion/export/endpoints reported provisionally). The subsequent full control-layout revision is compiled and locally checked but awaits Resolve appearance review in the planned integrated 1.70 development build. Factory-library re-evaluation follows that integration/deploy; current released fixtures/library remain 1.69.

The integrated 1.70 development build is now compiled; its new GPU/Resolve pass is pending user `make deploy`. Existing 1.69 fixtures remain in place, and the factory generator has not been run. Re-evaluation follows that deployment.
