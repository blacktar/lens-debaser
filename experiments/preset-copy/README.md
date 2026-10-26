# Resolve preset-copy test build

User-authorized on 2026-10-16. This isolated plug-in is named **Lens Debaser
Preset Copy Test**, with identifier `com.ldb.LensDebaser.PresetCopyTest`. It uses
released source revision 30902a7 plus the persistence fix and the byte-identical
passed 1.72 Metal library. It excludes the flare and Detail Transfer experiments.
The normal installed plug-in and release are not replaced.

## Behavior

The preset choice is now a nonpersistent, nonanimated loading action; host
restoration must not interpret its index as a request to apply Clean Slate.
Plugin-edited choice notifications do not apply a preset. Load/Save dialogs open
only for user actions.

A hidden persistent string stores the whole loaded preset catalogue, each
preset's name and original reference settings, and the selected entry, at full
round-trip precision. The actual rendered settings
remain the existing OFX parameters. Constructor, parameter-change and end-of-
batch reconciliation rebuild the active preset display and edited marker from
the stored reference without changing optical values or consulting a preset
file. The full loaded list is embedded, including when Custom or Clean Slate is
selected. Copied/reopened instances can select the other presets without
consulting files. Older test metadata containing only an active reference is
still readable; use Load once again to capture its entire folder catalogue. Custom and Clean Slate are handled separately.

Legacy instances without the new metadata retain their optical values and
show Custom when nonneutral. A preset name already lost by the old version
cannot be recovered from missing metadata. This experiment has a separate ID:
load a preset in the test plug-in before testing its copy behavior.

## Build and install

- Build: `python3 experiments/preset-copy/prepare.py`
- Quit Resolve, then run `./scripts/install-preset-copy-test.sh` from the repo root.
- Installer uses the prepared ZIP without rebuilding. It verifies package hash
  and ad-hoc signature, installs only the separately named test bundle, ensures
  readable permissions and retains any older test bundle as a timestamped backup.
- Restart Resolve and find **Lens Debaser Preset Copy Test** in OpenFX.

## Resolve checks — user pass recorded 26 October 2026

1. Load a preset again to capture the complete folder catalogue, then copy its
   node to another clip. Check all menu entries and switching between them,
   as well as the active preset name, all
   relevant optical values and appearance.
2. Repeat with Apply Grade from Previous Clip.
3. Change one optical control first; repeat both transfers. The edited preset
   name should remain marked, and the changed value should be preserved.
4. Undo/redo preset loading and copying. Confirm that optical values and the
   active/edited indication agree.
5. Save and reopen the project. Repeat with the original preset file temporarily
   unavailable; restoration must use the stored reference, not reload a file.
6. Exercise Custom and Clean Slate, including copying them. Loading another
   preset normally must still work.

## Checks completed

Plug-in builds for arm64. The exact metadata codec passes round-trip tests for
all reference fields, edited-versus-original separation, restoration independent
of files, and invalid/truncated/duplicate/future payload rejection. Tests do not
claim to simulate Resolve's notification sequence. The staged bundle's ad-hoc
signature is verified; its Metal library matches the accepted 1.72 SHA-256.
`out/build.json` records artifact hashes. The user confirmed “tested, works” on 26 October 2026 for the full-catalogue copy fix. No release promotion or guide update is implied.

Future test-build labels must include the release number, and handoff instructions must state the exact Resolve display name and include the project path before commands.
