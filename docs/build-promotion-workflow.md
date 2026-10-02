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

1. Update the guide's current build number, release date, and one-sentence
   high-level release summary together. The summary should describe the main
   user-visible changes without internal development terminology.
2. Build only the required guide renders and regenerate the HTML when its source
   content has changed.
3. Run `make guide-update-status` to review the exact hosted paths that changed,
   were added, or were removed since the last confirmed manual upload.
4. Run `make guide-update`. The resulting versioned folder and ZIP under
   `releases/user-guide-updates/` contain only the changed/new files, preserving
   their paths below `docs/user-guide`, plus a list of hosted files to delete.
   The ZIP has no version-named wrapper directory: extract it directly into the
   hosted guide root.
5. Upload and replace those files manually at the public guide host. Preserve the
   included directory structure, then check the live page, images, navigation,
   before/after controls, and download links.
6. Only after the public copy has been checked, run
   `make guide-publish-record`. This advances the local published baseline used
   by the next diff. Creating a bundle alone never marks it as published.

The guide update folder is an upload aid, not part of the downloadable OFX
distribution. Do not copy the full guide or its image library into the plug-in
release archive.

An unfinished or merely rendered visual pass is not a signed-off build and must
not be promoted, released, or pushed as the current public build.

### Next guide clarification

- Explain **Capture** and **Aperture & Bokeh** together so their different roles
  are immediately clear. Capture is a high-level coordination layer: focal
  length, f-stop, focus distance and capture format scale compatible field,
  focus, chromatic and illumination characteristics that are already enabled.
  It does not construct an aperture silhouette or shaped bokeh by itself.
- Explain that **Aperture & Bokeh** is the direct, opt-in reconstruction stage
  for defocused-light shape and pupil character, including blades, oval aspect,
  Cat-Eye, swirl, pupil shift, clipping and rim weighting. It does not describe
  the complete camera or capture setup.
- State that the groups complement one another: Capture establishes broad
  photographic behavior, while Aperture & Bokeh determines the appearance of
  shaped defocus when Aperture Response is enabled.
