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

Version 1.32 adds two native Color-page depth fixtures. They intentionally use
the same optical settings; only `depthSource` differs, so their results should
match when fed equivalent maps:

- `v1.32-Test-Depth-Alpha-Input.ldbpreset`
- `v1.32-Test-Depth-Second-RGB-Input.ldbpreset`
