# Lens Debaser engine ABI v17

ABI v17 makes highlight-scatter ownership explicit without changing the
784-byte Metal constant-buffer layout.

- `glareThreshold` reuses the reserved float at byte offset 648.
- Bloom reads only `bloomThreshold`.
- Glare reads only `glareThreshold`.
- Front-element wear and internal-element contamination use a separate optical
  scatter source instead of borrowing Bloom's threshold, radius and buffer.
- Legacy preset loading derives a missing Glare Threshold from the saved Bloom
  Threshold, preserving previously authored rendering. Current factory presets
  write Glare Threshold explicitly.
- Glare downsampling retains a restrained fraction of compact-source peak
  energy so small practicals remain responsive at large radii.

The new field defaults to `0.45`. Zero glare amount remains exactly neutral.
