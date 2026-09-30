# Build promotion workflow

Lens Debaser builds are promoted incrementally. A new build starts from the
last user-approved build and merges only files that were intentionally changed
for the new work. Passed files that were not modified remain the authoritative
versions; they are not regenerated, replaced, reformatted, or repackaged merely
because another part of the project changed.

## Generation rule

- Generate or rewrite an artifact only when its source or resulting content
  changed.
- Preserve byte-identical preset, guide, validation, resource, and packaging
  files, including their modification times where practical.
- Remove or archive a generated file only when the new build intentionally
  supersedes it.
- A broad generator may validate the complete collection, but it must merge
  changed outputs into the existing passed collection rather than recreating
  unchanged outputs.
- Build and release packaging may copy the complete approved product into a
  temporary staging directory, but must not mutate unchanged repository files.

## Promotion rule

1. Implement the scoped changes on top of the last passed build.
2. Run the relevant automated tests and performance benchmark.
3. Render only the new or affected visual-validation material.
4. Review the affected output in Resolve and obtain explicit user sign-off.
5. After sign-off, treat that exact combined state—changed files plus unchanged
   previously passed files—as the new passed build.
6. Deploy and package that signed-off state using the user-run Metal/Resolve
   workflow.
7. Commit the promoted source, presets, documentation, and intended release
   artifacts, then push the build update to GitHub.

## Externally hosted user guide

The user guide is published separately from the downloadable plug-in package.
For every signed-off build that changes the guide or any displayed image:

1. Build only the required guide renders and regenerate the HTML when its source
   content has changed.
2. Run `make guide-update-status` to review the exact hosted paths that changed,
   were added, or were removed since the last confirmed manual upload.
3. Run `make guide-update`. The resulting versioned folder under
   `releases/user-guide-updates/` contains only the changed/new files, preserving
   their paths below `docs/user-guide`, plus a list of hosted files to delete.
4. Upload and replace those files manually at the public guide host. Preserve the
   included directory structure, then check the live page, images, navigation,
   before/after controls, and download links.
5. Only after the public copy has been checked, run
   `make guide-publish-record`. This advances the local published baseline used
   by the next diff. Creating a bundle alone never marks it as published.

The guide update folder is an upload aid, not part of the downloadable OFX
distribution. Do not copy the full guide or its image library into the plug-in
release archive.

### Next guide revision

- In the Demonstrations `.demo-list`, make each control-group title an anchor
  link to that control group's detailed reference section in the same guide.
  Keep the preset description as ordinary text and use the reference section's
  existing stable `#` identifier so the links remain valid across updates.
- Apply the same pattern to the Cinematic Lenses preset list: make each preset
  title an anchor link to its corresponding preset visualization/reference
  entry. Keep the descriptive copy as ordinary text and use stable per-preset
  `#` identifiers.

An unfinished or merely rendered visual pass is not a signed-off build and must
not be promoted, released, or pushed as the current public build.
