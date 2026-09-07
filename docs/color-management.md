# Color-management contract

The plugin must expose an explicit **Input Working Space** setting matching the pixels supplied to the OFX node.

Supported working spaces for the first release:

- DaVinci Wide Gamut / DaVinci Intermediate
- ARRI Wide Gamut 3 / LogC3
- ARRI Wide Gamut 4 / LogC4
- ACES AP1 / ACEScct
- ACES AP1 / Linear (ACEScg)

LogC3 additionally exposes its Exposure Index. LogC4 is EI-independent.

The optical engine always operates in scene-linear AP1:

1. Decode the selected transfer function.
2. Convert the selected linear primaries to AP1.
3. Apply optical processing in linear AP1.
4. Convert AP1 back to the selected primaries.
5. Re-encode the selected transfer function.

The output encoding and primaries must match the input working space. Extended-range and negative values must not be clipped. Alpha passes through unchanged.

Input Working Space and Diagnostic View are OFX processing
context. They are deliberately excluded from `.ldbpreset` files, preset loading
must not modify them, and changing them must not mark the selected preset as
Custom. Resolve host events such as bypassing and re-enabling a node likewise
must not affect preset status.

Visual validation is blocked until round-trip and cross-encoding equivalence tests pass for every supported working space.

## Current implementation

The engine now brackets the optical passes with dedicated Metal conversion kernels. The source buffer is decoded and converted to linear AP1, all direct and scattered-light processing consumes that AP1 buffer, and the result is converted back to the selected input encoding. A zero Blend value copies the original encoded RGBA values exactly.

The first implemented LogC3 variant is EI800. Other LogC3 exposure indices remain an OFX/UI integration task and must use their corresponding published curve constants rather than relabelling EI800.

Automated GPU checks cover:

- neutral extended-range round trips in all five modes;
- bit-exact zero-Blend bypass in all five modes;
- equivalent decoded linear response to a neutral transmission operation;
- alpha preservation.

The matrices and curve constants are taken from the analytical CLF transforms in the Academy Software Foundation OpenColorIO Configuration for ACES. Camera gamut matrices are composed with the ACES AP0-to-AP1 matrix so the internal buffer is ACEScg/AP1 rather than ACES2065-1/AP0.
