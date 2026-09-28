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

## Version 1.51 active smoke tests

Only `v1.51-` fixtures remain in the active tests folder. Earlier build
fixtures are retained under `presets/archive/`.

For bokeh shape, use the isolated point-highlight aperture chart:

- `v1.51-Smoke-Bokeh-Swirl-Conservative.ldbpreset`
- `v1.51-Smoke-Bokeh-Swirl-Medium.ldbpreset`
- `v1.51-Smoke-Bokeh-Swirl-Extreme.ldbpreset`

For Petzval behavior, use both a portrait or textured central subject with
peripheral practicals and the ISO chart:

- `v1.51-Smoke-Petzval-Conservative.ldbpreset`
- `v1.51-Smoke-Petzval-Medium.ldbpreset`
- `v1.51-Smoke-Petzval-Extreme.ldbpreset`

The point chart judges pupil fill, orientation and smooth field progression.
The ISO chart judges curved focus and centre protection. Real footage is needed
to judge whether the resulting subject island feels photographically useful.

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
