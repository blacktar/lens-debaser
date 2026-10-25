# Signed installer workflow

The installer packages the approved 1.72 snapshot without rebuilding it or including experimental engine changes. Run from the repository root:

```sh
python3 scripts/notarization/build-installer.py
python3 scripts/notarization/notarize-installer.py --wait-seconds 60
```

Signing uses Developer ID Application and Developer ID Installer identities for team `CMRVMTA2G5`. Notarization uses the local Keychain profile `LensDebaser-Notary`. Keep credentials and private keys out of the repository. The commands require access to the normal user Keychain and Apple's network services.

The builder verifies the approved bundle and released ZIP, signs a staged copy, packages the factory presets, authoring kit, licence and notices, then extracts and verifies the resulting installer. Candidates and verification records are saved under `releases/installer-candidates/1.72/`. The latest record is referenced by `build/notarization/latest-installer.json`.

The notarization command records Apple's submission ID before waiting. Exit code 2 means processing is still in progress: run the same command again to resume that submission. Acceptance is followed by stapling, ticket validation, installer-signature verification and Gatekeeper assessment. An accepted submission alone is not the completion criterion; the final record must also show a stapled ticket and accepted Gatekeeper assessment.

## Installed contents

- Plug-in: `/Library/OFX/Plugins/LensDebaser.ofx.bundle`
- Factory presets, authoring kit, licence and notices: `/Library/Application Support/Lens Debaser/`
- Existing plug-in backup: `/Library/Application Support/Lens Debaser/Backups/Before-PKG-<timestamp>/`

Quit Resolve before installation. The installer preserves personal presets and does not re-sign installed code. Test installation, detection in Resolve and upgrade behaviour before public distribution. This exact approved binary requires Apple Silicon and declares macOS 26.0 as its minimum; the installer enforces that existing requirement.

## Deployment coverage

The product installer is the notarization submission container. Its embedded plug-in is Developer ID signed and checked as part of that submission. The inventory currently contains one native executable and no separate apps, helpers or dynamic libraries requiring additional signing. Presets, the authoring kit, licence, guide and web assets are data and do not need separate notarization.

The old release ZIP and shell installer remain historical artifacts. Do not use that shell installer for the signed package: it replaces the plug-in signature with an ad-hoc signature. Any future standalone plug-in ZIP or disk image must receive its own distribution verification and appropriate notarization/stapling workflow. A notarized PKG does not automatically convert old downloads into notarized releases.

## Verified distribution — 25 October 2026

Apple accepted submission `30070f9b-10ca-4fb9-8454-3621333fa8ce` with no reported issues. Candidate `20261025_v2` has its ticket stapled and validated; Gatekeeper reports Notarized Developer ID. The user confirmed installation and operation in Resolve. The package and checksum are uploaded to GitHub release `v1.72`. The updated guide is packaged for manual upload; publication is not yet confirmed.
