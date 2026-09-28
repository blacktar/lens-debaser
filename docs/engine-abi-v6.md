# Lens Debaser engine ABI v6

ABI v6 appends 32 bytes to `LDBOpticsParameters` for deterministic front-element
wear. All v5 offsets remain unchanged; the structure grows from 576 to 608
bytes.

The appended controls are `frontHaze`, `cleaningMarks`, `scratchAmount`,
`scratchDirection`, `damageScale`, `coatingWear`, `coatingWearScale`, and
`damageSeed`.

Wear is evaluated in normalized lens coordinates, so its pattern is fixed to
the virtual front element rather than to scene objects. It modulates forward
scatter, local contrast, transmission and flare color. Neutral values preserve
the v5 image exactly.
