# Lens Debaser

Lens Debaser is an Apple Silicon Metal/OpenFX lens-character plugin for
DaVinci Resolve. It models perceptually useful aspects of modern, vintage,
anamorphic and exotic optics, prioritising pleasing visual approximations and
interactive performance over scientific lens simulation.

Current private baseline: **1.25**.

## Implemented areas

- geometry, field curvature, swirl, astigmatism and directional smear;
- lateral and longitudinal chromatic aberration;
- MTF-inspired detail and microcontrast transfer;
- circular, polygonal, anamorphic and cat-eye aperture response;
- natural, optical and mechanical vignette behaviour;
- bloom, glare, spherical halo and transmission character;
- optional alpha-packed depth for focus-dependent aperture response and axial
  chromatic aberration;
- ACES AP1/ACEScct, DaVinci Wide Gamut/Intermediate, ARRI LogC3 EI800 and ARRI
  LogC4 working-space handling;
- editable external `.ldbpreset` preset files.

## Platform and dependencies

- Apple Silicon Mac;
- Xcode and the Apple Metal toolchain;
- DaVinci Resolve or Resolve Studio;
- Resolve's installed OpenFX 1.4 headers and support library.

The validation suite optionally uses local reference material that is not part
of this repository: an ISO 12233 chart, an iPhone DWG/Intermediate frame, an
ARRI LogC4 frame and ARRI's installed LogC4 display LUT. Override their paths
when needed:

```bash
make deploy \
  ISO_CHART=/path/to/ISO_12233-reschart.tif \
  REAL_FOOTAGE=/path/to/iphone-dwg-frame.tif \
  ARRI_FOOTAGE=/path/to/alexa35-logc4-frame.tif \
  ARRI_REVEAL_LUT=/path/to/ARRI_LogC4-to-Gamma24_Rec709-D65_v1-65.cube
```

## Build and validation

```bash
make validate
```

To validate, inspect the staged visual references and optionally install the
plugin into Resolve:

```bash
make deploy
```

Fully quit Resolve before deployment. Generated binaries, validation renders,
camera footage, LUTs, user presets and crash reports are intentionally excluded
from version control.

## Project status

This repository is private development work. No public redistribution or
open-source licence is granted at this stage.
