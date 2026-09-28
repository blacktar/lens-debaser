# Engine ABI v13 — vertical diffraction rays

Version 1.41 appends the vertical diffraction-ray controls while preserving the
size of the v12 parameter block.

ABI v13 replaces two reserved v12 parameter slots with independent vertical
diffraction-ray amount and length controls. The parameter block remains 784
bytes, so the Metal, engine, and OpenFX layouts stay binary-aligned.

The controls now feed the full-resolution analytic flare stage. Vertical rays
use a continuous narrow core and broad exponential tail around coherent sources;
they are no longer stretched sampled convolutions and therefore cannot expose
tap spacing as gradient steps. See `analytic-flare-model.md`.
