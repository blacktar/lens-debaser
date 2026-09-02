# Resolve host-validation checklist

## Open items

- Investigate why the supplied `ldb.png` bundle icon is not displayed for Lens
  Debaser in Resolve's Open FX menu. Verify what Resolve/Resolve Studio actually
  supports for an effect-list icon rather than assuming that macOS
  `CFBundleIconFile` or the generic OFX parameter-icon property controls it.
  Keep the supplied artwork unchanged unless a Resolve-specific size, format,
  filename, or bundle location is required.
- Append the current plugin version to the user-facing effect label everywhere
  it is appropriate, beginning with `Lens Debaser 1.2`. Keep the stable OFX
  identifier `com.ldb.LensDebaser` unchanged so projects continue to resolve the
  plugin across upgrades.
- Confirm the versioned name in Resolve's Open FX menu, effect inspector, plugin
  manager, and any host error messages after every version bump.

## Current host status

- Lens Debaser 1.2 is installed from `/Library/OFX/Plugins`.
- The installed arm64 bundle passes strict code-signature verification.
- Resolve discovers and loads the effect.
