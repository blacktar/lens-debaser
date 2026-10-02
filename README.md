# Lens Debaser

Lens Debaser is an Apple Silicon Metal/OpenFX lens-character plugin for
DaVinci Resolve. It models perceptually useful aspects of modern, vintage,
anamorphic and exotic optics, prioritising pleasing visual approximations and
interactive performance over scientific lens simulation.

Current development version: **1.67**.

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

## AI-assisted preset authoring

The [Preset Authoring Kit](preset-authoring/AI-PRESET-AUTHORING.md) lets users
describe a custom optical response to an AI assistant without asking it to
guess Lens Debaser's controls. It includes a machine-readable schema generated
from the current OFX implementation, a clean template and worked examples.
The AI client creates and checks the downloadable `.ldbpreset`; the user does
not need to assemble files in a text editor or use a command line.

Structural validation does not replace visual evaluation on suitable charts,
real images and moving footage.

Use the Preset Authoring Kit shipped with the Lens Debaser version being
targeted. Kits are version-specific because controls, ranges, choices and
dependencies may change between releases.

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

Builds are promoted incrementally: only intentionally changed artifacts are
regenerated or replaced, while unchanged files from the previous passed build
remain in place. After explicit visual sign-off, that merged state is deployed,
packaged, committed, and pushed to GitHub. See the
[build promotion workflow](docs/build-promotion-workflow.md).

The externally hosted user guide follows the same incremental rule. For a
signed-off build, `make guide-update` creates a versioned manual-upload folder
and matching ZIP containing only HTML and image files changed since the last
confirmed upload. The ZIP has no wrapper directory and can be extracted directly
into the hosted guide root.
After those files are uploaded and checked on the public page,
`make guide-publish-record` records the new baseline.

## Compiled releases

Create the complete versioned Apple Silicon distribution after updating the
version number:

```bash
make release
```

The command validates the engine, builds the Metal/OpenFX bundle and writes a
ZIP archive plus SHA-256 checksum into `releases/`. Each archive contains the
compiled OFX plug-in, compiled Metal library, factory presets, the AI Preset
Authoring Kit, release notes, third-party notices and a double-clickable
installer. The user guide and its example images remain online rather than
being duplicated in the archive.

Every release must regenerate the Preset Authoring Kit schema from the current
OFX controls and validate its clean template and all included examples before
packaging. Any added, removed, renamed, reranged or dependency-changed control
must also be reflected in the kit's user instructions and examples. The
`make release` dependency chain enforces schema regeneration and structural
validation; visual usefulness still requires review in Resolve.
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

Third-party software, platform, colour-science, test-chart and implemented
optical-model design acknowledgements are listed in
[`resources/THIRD-PARTY-NOTICES.txt`](resources/THIRD-PARTY-NOTICES.txt).
The notice distinguishes incorporated OpenFX support code from publications
that informed Lens Debaser's original real-time optical approximation.
The online user guide also contains a consolidated
[Acknowledgements & Credits](https://vidarandersen.com/dmz/lens-debaser-ofx/#credits)
section.
