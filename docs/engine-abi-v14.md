# Engine ABI v14 — analytic reflection train

ABI v14 uses the final v13 tail slot plus its structure padding for four
neutral-by-default internal-reflection controls. The shared parameter block
remains 784 bytes and every earlier field retains its offset.

- `anamorphicFlareGhostCount` selects one to six bounded reflection paths.
- `anamorphicFlareGhostSpacing` separates paths along the source/optical-centre
  axis in output pixels.
- `anamorphicFlareGhostScaleDecay` controls successive ellipse size.
- `anamorphicFlareGhostEnergyDecay` controls successive path energy.

Count one exactly selects the established single analytic ghost topology. No
scene pixels or reduced-resolution procedural clusters are reprojected. Every
path is evaluated as a smooth full-resolution filled ellipse with a restrained
rim, deterministic coating-tint variation and finite support.
