# Resolve host-validation status

Last updated: 2026-10-07

## Current accepted host status

Normal Lens Debaser 1.70/build 171 has user Resolve acceptance for the integrated
UI/projection and Frame Relative/Fixed Pixels sizing, including aperture, bloom,
glare and chromatic presets. All 76 revised cinematic presets, 12 new creative
presets and 44 demos are accepted. Guide accepted 2026-10-07; manual upload pending.
Exact integration snapshot: pass-104-integration-1.70-20261006-140927-527453.
Known thumbnail-scaling history and earlier diagnostics below remain historical;
no new sustained playback/export performance claim is made from short timings.

## Historical 1.69 host status

- Current released and host-validated build: Lens Debaser 1.69 (build 169).
- Stable OFX identifier: `com.ldb.LensDebaser`.
- Resolve discovers and loads the arm64 plug-in, displays the Lens Debaser icon,
  and reports version 1.69 after a full application restart.
- The installed bundle passes strict code-signature verification.
- The dedicated optional RGB `Depth Map` connector is the supported depth input;
  Resolve's blue key/mask connectors are not depth-map inputs.
- The 1.69 release includes Optical Drift and its approved demonstration and
  cinematic presets.

## Historical projection and initial 1.70 status

- Integrated 1.70 GPU tests passed and system deployment completed on 2026-10-05. Visual Pass 104: `pass-104-integration-1.70-20261005-175754-80991`. Installed metadata and report/snapshot verified. New-layout and integrated Resolve review still pending; public approved release remains 1.69. Timing outliers prevent general performance claims.

- First 1.70 deploy attempt stopped before GPU work/install on pre-existing factory range issues. Integration check now records 59 unchanged released-preset flags for the upcoming review, while new/modified or malformed presets remain blocking. User must rerun `make deploy`. No 1.70 host pass is claimed.

- Public and host-validated release remains 1.69. Candidate identity is
  `com.ldb.LensDebaser.ProjectionTest`, internal test bundle 1.69.1 / 16901.
- User CLI GPU validation passed on 2026-10-04: Off/zero Amount/zero Angle preserve
  released neutral and optical outputs bit-for-bit, both models activate
  independently, all 24 endpoint cases are finite (including displaced axes),
  and the full engine regression suite passes. Twelve example images and three
  benchmarks are preserved in the original immutable Visual Pass 103.
- User Resolve checks passed visually: 00–03 identical; model/framing comparisons
  expected; preset group expansion fixed; Amount asterisk edit/restore and custom
  save/reload work; 12 with Projection Off looks perceptually like 11.
- Motion/export/project persistence and endpoints received provisional user
  “seems to work / as expected” results. Preset 08 at 89°/100% magnifies to
  unusable proportions; this is expected behavior, not a creative recommendation.
  Requested range stays 0–89°, preferred factory examples 55° Balanced.
- Full UI audit implemented on 2026-10-05: 159 controls in a shared declarative
  hierarchy with six top sections, corrected names and ordering, separate flare
  subgroups and consistent configured-child/ancestor expansion. Candidate
  compilation, coverage/hierarchy/dependency tests, host-only mapping and strict
  signature pass. Shader unchanged; no new renders or timing runs required.
- Revised layout snapshot:
  `outputs/engine-validation/passes/pass-103-projection-resolve-candidate-20261005-092459-control-layout-33978/`.
  Revised Resolve appearance/nesting still needs checking. User requests that the
  next integrated development/deploy build be 1.70; candidate UI testing does not
  substitute for an integrated 1.70 pass.
- 1.70/build 170 is now integrated and locally compiled/signed under the stable
  identity, with OFX minor version 70. It has not been installed or GPU-validated
  yet. The user runs `make deploy`, reviews the new Visual Pass 104, and installs
  through its CLI prompt. Existing 1.69 factory files remain unchanged.
- Next: validate and deploy integrated 1.70, then re-evaluate every factory preset
  under the staged workflow in `docs/build-promotion-workflow.md`. Benchmark and
  inspect changed/new presets using established HTML before/after comparisons.
  Public release/preset promotion still depends on user agreement.

## Latest passed Resolve checks

- Continuous field/aperture PSF behavior passed visual and host inspection.
- Optical Drift passed on synthetic charts and real footage. Its examples were
  intentionally heavy-handed for diagnosis; released preset levels were reviewed
  independently.
- Demo 27 and Demo 28 passed; revised Demo 32 passed after iteration.
- The Internal Field Edge FX signature preset passed and shipped.
- Preset editing retains the loaded preset name with an asterisk and removes the
  asterisk when controls return to the loaded state.
- Demo 25 opens all required influencing control groups and has sufficient visible
  rotational character.
- Playback, parameter interaction and relevant depth-input behavior passed in the
  user's Resolve installation.

## Known host issue for a future build

- Resolve thumbnails may apply Lens Debaser at the wrong scale. This suspected
  regression was explicitly allowed to remain in 1.69 because it does not prevent
  the current Preset Authoring Kit from working. Reproduce and fix it before
  claiming it resolved.

## Validation required after every version bump

1. Fully quit Resolve before installing the new bundle, then restart it.
2. Confirm the new version in the Open FX menu, inspector and plug-in manager.
3. Confirm existing projects still resolve the stable OFX identifier.
4. Load representative demonstration, cinematic, signature and depth-aware presets.
5. Check full-resolution output, viewer interaction, playback and thumbnails.
6. Confirm preset name/asterisk behavior after editing and restoring controls.
7. Verify the installed arm64 bundle's code signature.

## Historical depth behavior retained by the current engine

- `Input Near`, `Input Far` and `Focus Depth` operate in normalized 0–1 map space.
- Near Black and Near White interpretations invert as expected in the Depth Input
  diagnostic.
- Depth Edge Protection and Depth Edge Softness control cross-layer sampling.
- Defocus Amount and Depth Rejection diagnostics expose the active response.
- Depth-aware aperture, longitudinal chromatic aberration, bloom and glare have
  passed moving-footage inspection with Resolve AI depth maps.

## Deployment workflow correction (2026-10-05)

1.70 is installed and GPU validation completed in Pass 104. Integrated Resolve
layout/compatibility review and explicit benchmark/visual acceptance remain pending.
Validation now uses `make validate`; `make deploy` only installs an explicitly
passed snapshot, without rendering or opening reports. The existing installation
does not need repeating for this workflow correction.

## 1.70 initial expansion correction (2026-10-06)

User reports Presets and Input & Diagnostics incorrectly collapsed on initial
load. Descriptor creation opened only Setup and Output; its layout-group lookup
ignored the original child-group open defaults. Corrected descriptor defaults
to share the same always-open policy as preset expansion: Setup, Presets,
Input & Diagnostics and Output. Host compiled; layout tests confirm both initial
and neutral/configured-preset expansion. No engine/shader change, new GPU run,
deployment or user acceptance. Existing Pass 104 remains historical evidence;
its bundle predates this host correction. Resolve verification remains pending.
