# Engine ABI v10 — structured anamorphic flare

Version 1.40 appends structured flare controls to `LDBOpticsParameters` without
changing any version-1 through version-9 offsets or meanings. Existing presets
retain the established single horizontal flare because every new contribution
defaults to neutral.

The new controls are:

- **Flare Core** — concentrates high-energy colour inside the broad streak;
- **Flare Asymmetry** — shifts the convolved response to create an unequal
  left/right tail;
- **Ghost Amount** — adds a centre-relative internal reflection derived from
  the same thresholded highlight source;
- **Ghost Position** — controls source-to-ghost motion, with negative values
  moving the reflection opposite the source across the optical centre;
- **Ghost Scale** — scales the reflection around the optical centre;
- **Ghost Color** — independently colours the internal reflection.

The implementation reuses the existing flare scatter buffer in the composite
stage. It adds no additional full-frame scatter allocation and keeps the
established depth-edge protection for the primary streak.
