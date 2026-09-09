# Lens Debaser

Lens Debaser is an Apple Silicon Metal/OpenFX lens-character plugin for
DaVinci Resolve. It models perceptually useful aspects of modern, vintage,
anamorphic and exotic optics, prioritising pleasing visual approximations and
interactive performance over scientific lens simulation.

Current development version: **1.35**.

Testers can open the standalone [Lens Debaser user guide](docs/user-guide/Lens-Debaser-User-Guide.html) for the complete workflow, control reference, depth setup, and preset catalogue.

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

The generated external preset library contains 96 files in
`presets/demonstrations` and `presets/cinematic-lenses`: sixteen families in
each library, with Subtle, Medium, and Caricature variants. Installation copies
them outside the OFX bundle to
`~/Library/Application Support/Lens Debaser/Presets`.

## Platform and dependencies

- Apple Silicon Mac;
- Xcode and the Apple Metal toolchain;
- DaVinci Resolve or Resolve Studio;
- Resolve's installed OpenFX 1.4 headers and support library.

The repository includes the three image references required by the validation
suite: an ISO 12233 chart, an iPhone DWG/Intermediate frame, and an ARRI LogC4
frame. ARRI's LogC4 display LUT is loaded from the standard Resolve LUT
installation. Override the reference directory when needed:

```bash
make deploy REFERENCE_DIR=/path/to/reference-folder
```

Individual files can still be overridden when needed:

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

Fully quit Resolve before deployment. Validation renders, additional camera
footage, LUTs, user presets and crash reports are intentionally excluded from
version control.

## Compiled releases

Create the complete versioned Apple Silicon distribution after updating the
version number:

```bash
make release
```

The command validates the engine, builds the Metal/OpenFX bundle and writes a
ZIP archive plus SHA-256 checksum into `releases/`. Each archive contains the
compiled OFX plug-in, compiled Metal library, factory presets, standalone user
guide and a double-clickable installer. Versioned release archives are kept in
the repository so testers do not need Xcode or the Resolve OpenFX SDK.

## License

Lens Debaser is licensed under the
[Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International
License](https://creativecommons.org/licenses/by-nc-sa/4.0/). You may share
and adapt the project with attribution for non-commercial purposes, provided
derivative work is distributed under the same license. See [LICENSE](LICENSE)
for the complete legal terms.
