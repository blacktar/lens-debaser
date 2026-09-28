# Engine ABI v12 — anamorphic flare thickness

ABI v12 adds `anamorphicFlareThickness` after the v11 layered-flare controls.
The neutral value is `1.0`, which preserves the v11 vertical flare footprint.
Values below one create thinner primary, layered, and secondary streaks; values
above one broaden them. Three reserved floats retain 16-byte struct alignment.

The parameter block is 784 bytes. `anamorphicFlareThickness` begins at byte
offset 756. Hosts and Metal kernels must agree on ABI version 12 before render.

The long-flare blur also uses near-continuous sampling on its reduced-resolution
buffer. This prevents compact highlights from resolving into periodic vertical
cutoffs at large horizontal flare radii.
