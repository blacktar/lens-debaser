# Lens Debaser

Lens Debaser is an Apple Silicon Metal/OpenFX lens-character plugin for
DaVinci Resolve. It models perceptually useful aspects of modern, vintage,
anamorphic and exotic optics, prioritising pleasing visual approximations and
interactive performance over scientific lens simulation.

Current development version: **1.57**.

Read the online [Lens Debaser user guide](https://vidarandersen.com/dmz/lens-debaser-ofx/) for the complete workflow, control reference, depth setup, and preset catalogue.

## Implemented areas

- geometry, field curvature, swirl, astigmatism and directional smear;
- lateral and longitudinal chromatic aberration;
- coherent directional prism refraction with edge placement, softness and
  wavelength dispersion;
- MTF-inspired detail and microcontrast transfer;
- circular, polygonal, anamorphic and cat-eye aperture response;
- natural, optical and mechanical vignette behaviour;
- bloom, glare, spherical halo and transmission character;
- coherent-source anamorphic flare with full-resolution analytic diffraction
  and bounded internal-reflection primitives;
- optional alpha-packed depth for focus-dependent aperture response and axial
  chromatic aberration;
- ACES AP1/ACEScct, DaVinci Wide Gamut/Intermediate, ARRI LogC3 EI800 and ARRI
  LogC4 working-space handling;
- editable external `.ldbpreset` preset files.

The generated external preset library contains 104 files in
`presets/demonstrations` and `presets/cinematic-lenses`: thirty-one single,
moderate educational demonstrations, twenty-four cinematic-lens families with
three independently authored variants each, and the Bodycam Edge Stress
signature preset. The cinematic library includes the three-tier Edge Prism
Glass family for the coherent prism controls. Installation copies
them outside the OFX bundle to
`~/Library/Application Support/Lens Debaser/Presets`.

## Platform and dependencies

- Apple Silicon Mac;
- Xcode and the Apple Metal toolchain;
- DaVinci Resolve or Resolve Studio;
- Resolve's installed OpenFX 1.4 headers and support library.

The repository includes the redistributable charts and iPhone images used to
build the online guide. The complete visual-validation suite additionally uses
local lens-reference footage and an ARRI LogC4 frame that are not distributed
with the project. ARRI's LogC4 display LUT is loaded from the standard Resolve
LUT installation. Supply the local validation reference directory when needed:

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
compiled OFX plug-in, compiled Metal library, factory presets, release notes,
third-party notices and a double-clickable installer. The user guide and its
example images remain online rather than being duplicated in the archive.
Versioned release archives are published as GitHub release assets so users do
not need Xcode or the Resolve OpenFX SDK. Download the current build from
[GitHub Releases](https://github.com/blacktar/lens-debaser/releases).

## License, credits and third-party notices

Lens Debaser is licensed under the
[Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International
License](https://creativecommons.org/licenses/by-nc-sa/4.0/). You may share
and adapt the project with attribution for non-commercial purposes, provided
derivative work is distributed under the same license. See the repository
[LICENSE](LICENSE) for the complete legal terms.

The included Milan images captured with an iPhone 17 Pro and 1.55× anamorphic
adapter were created by Vidar Andersen and are distributed under this same
license. Their asset-level attribution is recorded in
[`inputs/redistributable/README.md`](inputs/redistributable/README.md).

Third-party software, platform, colour-science and test-chart acknowledgements
are listed in [`resources/THIRD-PARTY-NOTICES.txt`](resources/THIRD-PARTY-NOTICES.txt).
The online user guide also contains a consolidated
[Acknowledgements & Credits](https://vidarandersen.com/dmz/lens-debaser-ofx/#credits)
section.
