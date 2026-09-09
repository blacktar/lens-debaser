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

Version 1.35 uses only the verified dedicated RGB Depth Map connector. Resolve's
blue key/mask inputs are not depth sources.

Version 1.33 adds three boundary-conditioning fixtures. Use the same native
depth input for all three and compare foreground/background contamination:

- `v1.33-Test-Depth-Edges-Understated.ldbpreset`
- `v1.33-Test-Depth-Edges-Mid.ldbpreset`
- `v1.33-Test-Depth-Edges-Max.ldbpreset`
