# Build promotion workflow

Lens Debaser builds are promoted incrementally. A new build starts from the
last user-approved build and merges only files that were intentionally changed
for the new work. Passed files that were not modified remain the authoritative
versions; they are not regenerated, replaced, reformatted, or repackaged merely
because another part of the project changed.

## Established procedure comes first

Before choosing an approach, check the project handoff, workflow documents and
previous comparable work for established rules and procedures. Follow them when
they still serve the purpose. If an improvement or replacement seems useful,
explain the proposed change and ask the user before departing from an established
step, process or rule. Do not independently discard or silently substitute them.
This approval is for a procedural departure, not routine work already authorized
within the existing procedure.

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

## Working reports and passed archives

- Comparison reference rule: a NEW preset’s first attempt compares visually with the unprocessed original image. While that new preset remains unpassed, each iteration compares with its immediate previous rendered state. For changes to an EXISTING PASSED or RELEASED preset, use that preset’s LAST PASSED visual output and benchmark measurements as the fixed reference throughout candidate iteration; never replace it with an unpassed intermediate result or regenerate it. Keep OK/passed presets unchanged during other presets’ iterations. Maintain the appropriate task HTML until sign-off; only accepted evidence becomes future benchmarking reference material.

After the user signs off new presets as passed, add their exact approved renders, recipes, engine/source context and standalone timings to the benchmark HTML as references for future build comparisons. Until sign-off, keep them in their separate new-preset review. Do not invent a previous-release baseline or percentage change when promoting a newly passed preset; its accepted state becomes the reference for subsequent builds.

Use a NEW HTML for NEW things to inspect and iterate on, then keep revising that new task’s canonical HTML. Use the existing release benchmarking HTML ONLY for the previous release baseline versus the new candidate release. Do not append new preset families or unrelated experiments to it, and do not invent a baseline for new work. Archive only explicitly passed states.

Revise one canonical working comparison HTML in place. Only a state explicitly
agreed as passed becomes a retained comparison archive for later versions.
Unpassed iterations are working material, not historical comparison baselines;
do not create a new permanent review report/archive for each revision. Preserve
accepted states and their exact preset, engine, source and benchmark evidence.
Existing material is not deleted automatically; cleanup requires a scoped review.

## Promotion rule

Benchmarking is required for engine changes and changed or new cinematic presets.
Educational demo presets require visual review, not preset benchmarks. Review and
validate every current cinematic preset, including every strength; unchanged recipe
values do not establish compatibility after an engine change. Reuse exact matching
passed evidence, and add targeted renders only where current coverage is missing.
Cinematic before/after output and speed comparisons use the same actual footage
frame on both sides. Synthetic charts remain supplementary diagnostics for
geometry, pupil shape and highlight behavior; their timings do not replace
actual-footage benchmarks. At the cinematic preset review stage, keep the exact
established speed-test image, dimensions, encoding/conversion and display path
fixed across the entire comparison; baseline and candidate must receive identical
input pixels. Do not select different sources by preset family or replace the
fixed image with synthetic fixtures. Synthetic sources are appropriate for new
feature/model experiments and targeted diagnostics. Distinguish repeated-frame GPU timings from video
decoding, motion/export testing and native-resolution playback.


1. Implement scoped changes on top of the last passed build.
2. Test, benchmark and visually inspect the affected outputs. Iterate until
   Codex and the user agree that the exact state passes; retain passed unchanged
   material and repeat only checks affected by revisions.
3. Record that agreement, then run `make deploy` for the agreed state.
4. Inspect the deployment script output and retain it as additional evidence
   informing benchmark interpretation. Deployment follows acceptance; its output
   can reveal issues requiring further investigation or another iteration.
5. Verify the installed state in Resolve. Record deployment and host results
   separately from the pre-deployment test/benchmark/visual acceptance.
6. Package, commit and push only when the agreed release workflow is complete.

## Externally hosted user guide

The user guide is published separately from the downloadable plug-in package.
For every signed-off build that changes the guide or any displayed image:

1. Update the guide's current build number, release date, and one-sentence
   high-level release summary together. The summary should describe the main
   user-visible changes without internal development terminology.
2. Build only the required guide renders and regenerate the HTML when its source
   content has changed.
3. Present the complete local guide, including current text, generated UI approximations and
   visual renders, for user review. Wait for explicit guide acceptance before
   packaging its upload diff. Then run `make guide-update-status` to review the exact hosted paths that changed,
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

## Handoff-document rule

Before ending a substantial development session or moving to a new context,
bring the active Markdown continuity documents up to date:

- `LDB_HANDOFF.md` must identify the released baseline, exact dirty files,
  experimental versus promoted work, latest evidence and the next safe action.
- `docs/resolve-host-validation.md` must identify the current host-validated
  version, passed checks, known host issues and checks required next time.
- `presets/tests/README.md` must identify the version and scope of fixtures that
  are actually present in the active test folder.
- `README.md` must match the current public release and shipped feature/library
  counts.

Audit all project Markdown for contradictory “current version”, “open items” or
“next step” statements. Historical ABI, model-audit and roadmap documents remain
historical and should not be rewritten merely to mention the newest release.
Run `git diff --check` after updating the handoff documents.

### Next guide clarification

- In the AI-assisted preset section, suggest optionally uploading one or more
  reference images to the AI client when the user wants to approximate a
  particular optical treatment. Explain that the image helps the assistant
  identify visible traits and propose a Lens Debaser preset, but cannot reveal
  the original lens, node tree, motion behavior or hidden settings with
  certainty. Encourage users to include both the desired reference and a
  representative frame from their own footage when possible, then evaluate the
  generated preset in Resolve and request focused revisions.
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

## 1.70 integration, factory-library review and release sequence

Agreed with the user on 2026-10-05. The next integrated development/deploy version
is 1.70 (build 170); the public approved baseline remains 1.69 until promotion.
The complete candidate control-layout audit is implemented and compiled. The
new layout will receive its Resolve appearance check in the integrated build.

1. Integrate projection and the audited UI into the stable product identity.
   Preserve parameter IDs, preset keys, choice indices, neutral defaults and the
   ABI. Keep a recoverable 1.69 bundle and prior validation outputs. Version-match
   the build metadata and development documentation. Produce a new named,
   immutable integration validation pass using `make validate` for user-run GPU
   work. Review benchmarks and visuals before explicit acceptance; record the
   accepted inputs with `./scripts/pass-1.70-integration.py --accept`. Only then
   use `make deploy`, which installs that snapshot without rebuilding, rendering
   or opening a validation report. Check existing project nodes,
   old presets, Off/zero behavior, UI ordering/nesting, group expansion and
   preset state. Do not treat candidate checks as a complete integrated-build pass.
2. Inventory and re-evaluate every current factory preset, including all
   demonstrations, cinematic profiles and signatures. Give every entry a
   recorded decision: keep, revise, replace or retire with rationale. Do not
   blindly add projection to all presets or invent physical lens attribution.
   Reuse passed unchanged images; render only settings or outputs that change.
   Native resolution is required for fine-detail/sharpness decisions; 960px is
   suitable for guide examples and framing/character review.
3. Add focused demonstration presets for projection model, amount, field angle
   and framing, plus controls whose presentation or demonstration needs updating.
   Reconsider every creative preset for benefits from the new engine, remake
   those that benefit, and add creative examples showing distinctive new value.
   Keep numerical endpoint tests separate from recommended creative presets.
   Preserve the approved 0–89° field-angle range; 89°/100% magnification is not a
   useful default just because it is finite. Preferred examples start at 55°,
   Balanced, Amount 20/45/70%.
4. Validate and benchmark changed/new presets on a small representative set.
   For revisions, preserve the exact old preset, engine and render as the
   comparison baseline. Use matched sources, resolution, input encoding and
   optical conditions; identify whether a comparison measures engine changes,
   preset changes or the combined user-visible result. Repeat paired timing
   runs where necessary; show GPU and wall times and percent changes, including
   variability. Do not claim speedups from noisy negative deltas. Present before/
   after swipe comparisons with on-image labels, natural ratios and inline
   readable validation/benchmark tables in the established HTML format. No
   CSV/log/data links. Iterate only failing or altered examples, retaining passed
   material. Record user visual/preset acceptance per entry before promotion.
5. After agreement on the changed/new library, finalize the exact integrated
   source, factory presets and counts. Update and validate the AI Preset Authoring
   Kit/schema/templates, including projection choices, units, defaults, ranges
   and the revised UI descriptions. Avoid hardcoded stale factory counts in
   build/package checks. Complete the relevant regressions, sustained benchmark,
   signed bundle/architecture/identity checks and final Resolve smoke pass.
   Recheck the known thumbnail-scaling issue; fix it or explicitly retain its
   documented status rather than claiming it resolved. Check installation,
   preset discovery, project reload, viewer/playback/export and rollback.
6. Build and verify the approved 1.70 release package and authoring-kit package.
   Update the user guide for the new UI, feature semantics, release metadata and
   final preset catalogue. Prepare focused rendering scripts for the user to run
   with their Metal device; generate only added/changed visualizations and merge
   with unchanged passed guide assets. Check HTML, images, navigation, comparison
   sliders, counts and download links. Create the upload diff with `make
   guide-update-status` and `make guide-update`; preserve the last confirmed
   published baseline. The user uploads/publishes the guide manually, checks the
   live result, then records publication with `make guide-publish-record`.
7. Once the release state is approved, commit and push the intended source,
   presets, tests, docs and release artifacts. Inspect the staged list; exclude
   historical untracked 1.36/1.57 archives and unrelated local material. Check
   archive contents, checksums, version consistency, clean-install paths and
   public download references. Record exact release/publication results and any
   remaining issue in continuity docs. Never mark guide publication complete
   merely because the upload diff or release archive was created.

Codex maintains the per-preset decisions, validation evidence and remaining-step
checklist, and reminds the user when a required release/publishing step is missing.
The user's request authorizes this staged workflow; release/preset agreement gates
remain explicit. No release package, public guide promotion, commit or push is
claimed by recording this plan.

## Next feature after 1.70 acceptance

After 1.70 is signed off as passed, prioritize optional automatic cropping of
unusable lens-produced edges, with manual override/fine-tuning. Investigate the
user-reported issue that zoom/crop before the effect merely changes its input
and Lens Debaser then applies its mapping over that current image again. Prefer
an explicit final framing/crop stage whose optical coordinate domain stays
consistent, and reproduce Resolve transform/node ordering before deciding the
implementation. Follow the focused endpoint experiment and approval workflow;
this feature is not part of the current 1.70 scope.

### Benchmark interpretation

Judge benchmark changes by absolute baseline/candidate time and delta in milliseconds first; percentages are secondary context. Consider run variability and practical impact before requesting investigation or blocking acceptance. Never flag a small absolute increase solely because its percentage is large; no universal millisecond cutoff is implied. Report GPU and wall times separately and retain their measured spread.

## Required next guide revision: preset navigation and completeness (2026-10-07)

- Menu anchors for Cinematic Presets and Effect Demo Presets must land on their
  respective list summaries. Give the demo list its own stable anchor; keep
  visual galleries separately labeled and linked.
- Audit every shipped demo against the list and visual cards. Current guide has
  30 summary entries for 44 demos: 31 Prism Refraction, 33–38 Projection,
  39 Vintage Caricature, 40 Anamorphic Fringing, 41–42 Optical Drift,
  43 Linear Edge Prism and 44–45 Depth are missing.
- Existing visuals33–43 have generic applied-preset text only. Introduce what
  each demonstrates, prerequisites and how to judge it; link summary to visual
  and visual back to summary/reference.44–45need documented depth-input examples,
  not fabricated ordinaryRGB illustrations.
- Check all cinematic families and all visualisations for orphaned entries,
  stale/misleading links and missing introductory text. Validate correspondence
  between shipped presets, list summaries and supported visual evidence.
- Preserve published1.70guide and baseline. Prepare changes for next revision,
  with review before diff; no extra rendering until justified missing inputs.

### Future guide header exploration (2026-10-07)

- Inspect https://tomacco.github.io/amazing-glass/ as a possible treatment for the
  decorative “Ldb” letters. Evaluate appearance, readability, browser support and
  performance before proposing adoption; no current design change authorized.
- Review decorative “Ldb” sizing/placement specifically on smartphone portrait
  screens. Keep the letters visually meaningful rather than shrinking them to an
  almost irrelevant size. Preserve readable headline, copy and buttons.
- Use a separate header preview and user visual approval before changing the
  published guide or packaging its upload diff.

## 1.72 release work after normal Resolve acceptance (2026-10-07)

User explicitly requests, after the integrated build passes its Resolve check:

- Package the approved release binaries, following existing validation, exact
  snapshot, signing, version/build, archive and checksum procedures. Keep old
  release archives and passed comparison evidence intact.
- Update the user guide with a Final Framing / Auto Fill reference section:
  Auto Fill Frame, Adjust Auto (signed; available only when Auto Fill is on),
  Manual Crop (available only when Auto Fill is off), zero defaults, independent
  retained values, edge removal, composition/detail tradeoffs and render cost.
- Add an Auto Fill demonstration preset and visual comparison. Explicit exception
  to the usual five-source guide rule: this demonstration needs ONE image only.
  Reuse an existing extreme preset's exact rendered Off result as reference and
  compare with Auto Fill on using the same optical preset/source/settings. Do
  not benchmark the demo preset or regenerate the existing Off reference.
- Test Amazing Glass treatment of decorative Ldb lettering in a separate header
  preview; address portrait-phone letter scale/placement. Do not change the
  published guide until the user approves the preview and complete guide.
- Include the previously recorded preset-summary anchors/orphaned-demo audit
  in the next guide revision. Update AI preset-authoring kit/schema for the new
  controls and version; review existing presets for compatible neutral framing
  rather than changing their optical looks without approval.
- Complete guide review/pass before packaging the upload diff ZIP. User uploads
  manually; verify live and record publication only after their confirmation.

### Cinematic guide examples (2026-10-07)

User requests every available Subtle, Medium and Caricature member of each cinematic family in the guide, each with both charts and three iPhone images. Treat members as distinct optical interpretations, not merely amplified controls. Reuse approved matching outputs; render only missing pictures. Single-version presets remain signature examples. This supersedes the guide generator’s previous Medium-only selection.

### Glass header deferred until after 1.72 (2026-10-07)

User explicitly defers glass lettering to a separate experiment after this release. No glass runtime, mask or rendering dependency belongs in the 1.72 guide. Retain original Ldb typography, size and placement and the approved Internal Field Edge FX ISO background. Retain the preview intro paragraph order (Because all cameras before the free/source paragraph) and link only Preset Authoring Kit. Any future glass approach must demonstrate visible optical effects and acceptable responsiveness in a separate audition before integration. Complete 1.72 guide renders, review, upload diff and manual publication first.

### Next guide revision: GitHub issue tracker (2026-10-07)

User requests a clear link to https://github.com/blacktar/lens-debaser/issues for bug reports, feature requests and related feedback in the next version of the user guide. Update relevant support/reporting text during that revision. Do not alter the already-approved 1.72 upload diff for this deferred change.
