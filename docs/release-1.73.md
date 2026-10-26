# Lens Debaser 1.73

This release preserves the full loaded preset list when copying a node, applying the previous clip's grade, or reopening a project. Active selection, reference settings and manual adjustments are preserved. Loaded entries are stored with the node; the original preset files are not needed to restore them.

For nodes created in older versions, use Load again to capture the complete preset folder. Missing metadata from an older node cannot be recovered automatically.

The isolated full-catalogue test was confirmed working by the user on 26 October 2026. The stable build changes its label, bundle version and host-reported version to 1.73, and uses the normal stable plug-in identifier. The exact 1.72 optical library is retained. Experimental flare and Detail Transfer changes are excluded. The user confirmed installation of the final stable-identity package works on 26 October 2026. Installer revision 20261026_v2 removes development-only README and welcome wording; plug-in behavior is unchanged.

## Reproducible release build

From the repository root:

```sh
python3 scripts/release-1.73/prepare.py
python3 scripts/notarization/build-installer-1.73.py
python3 scripts/notarization/notarize-installer.py --wait-seconds 60
python3 scripts/release-1.73/verify.py
```

The preparation script reconstructs release source revision `30902a7`, overlays the tested persistence code and version changes, and reuses the checksum-verified optical library from the original 1.72 release ZIP. That ZIP and its checksum must be present in `releases/`. The source archive includes the matching fixed optical library; after extracting it, use `MACOSX_DEPLOYMENT_TARGET=26.0 make ofx` with full Xcode and the Resolve OpenFX SDK installed.

The source checkout's unrelated engine experiments are not used for this release. Use the dedicated release recipe rather than the root default build.

## Distribution verification

Apple accepted submission `f7697354-9f68-4872-b3f3-e97aa557fa3c` without reported issues. The installer ticket is stapled and validated, and Gatekeeper accepts it as Notarized Developer ID. Extracted-payload checks passed: stable name/identifier/version, arm64, signature, executable hash, exact optical-library hash, 133 factory presets and matching authoring kit. Metadata codec tests passed.

Guide changes: 1.73 release summary prepended while retaining previous summaries, download updated, and Presets description explains full-list persistence and legacy-node reloading. The guide diff contains only index.html and awaits manual deployment confirmation.
