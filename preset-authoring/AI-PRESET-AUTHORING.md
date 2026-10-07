# Create Lens Debaser presets with an AI assistant

> **Highly experimental:** AI-assisted preset generation can produce invalid
> files, misunderstand dependencies, choose visually poor combinations, or
> behave unpredictably across different footage. Treat every generated preset
> as an untrusted creative starting point. Validate it, inspect it at full
> resolution and in motion, and retain known-good versions while testing.

Lens Debaser presets are small, editable text files. You can describe an optical response in ordinary language and ask an AI assistant to create a finished, downloadable `.ldbpreset`, check it against the supplied schema, and revise it after you look at the result in Resolve. The AI client performs the file creation; you do not need a command line, programming knowledge or a text editor.

This is creative optical design, not a request for a scientifically exact lens prescription. The useful target is a coherent, controllable image response that renders quickly and behaves well across faces, highlights, texture, motion and frame edges.

## Give the AI the right context

Use the Preset Authoring Kit that matches the Lens Debaser version for which
you are creating the preset. Do not assume that the newest kit is compatible
with an older installed plug-in, or that an older kit describes a newer one.
Controls, ranges, menu choices and dependencies may change between releases.
The kit included inside each release archive is the authoritative package for
that version.

Provide these files in the same conversation:

1. `Lens-Debaser-Preset-Schema.json` — current controls, ranges, choices, defaults, dependencies and performance guidance.
2. `Clean-Slate-Template.ldbpreset` — the required file format.
3. One or two example presets, if their structure is relevant to the effect you want.
4. Optionally, a clean reference frame and a visual reference for the desired character.

Do not ask the AI to invent control names. A valid result may use only keys listed under `controls` in the schema.

## Reusable prompt

> Design one Lens Debaser preset for the attached creative brief. Use only controls in the supplied Lens Debaser schema and obey every range, choice and dependency. Optimise for a perceptually convincing optical approximation and responsive playback, not scientific ray tracing. Activate the fewest control groups needed. Do not serialize Input Working Space, Diagnostic View, unchanged defaults, or imaginary controls. Preserve neutral colour unless the brief explicitly asks for a tint. Avoid extreme edge displacement, clipped highlights, obvious layered blur, repeated ghost steps and uniformly applied chromatic fringing. If a shaping control needs an enabling amount, include that amount explicitly. Return: (1) a short explanation of the optical strategy, (2) expected visual and performance trade-offs, (3) suitable footage and chart tests, and (4) a validated, downloadable `.ldbpreset` file beginning with `LensDebaserPreset=2`. Do not ask me to create, rename or edit the preset file manually.

Then add your brief. Describe what should happen in the centre, toward the edges, around highlights, in and out of focus, and in motion. Say whether the result should be restrained, pronounced or intentionally extreme.

## A productive iteration loop

1. Begin with one clear optical idea. Avoid asking for every aberration at once.
2. Ask the AI assistant to validate the generated file against the attached schema before delivering it.
3. Test it on a face, fine detail, hard contrast edges, small highlights and moving footage. A chart alone cannot establish whether an effect feels photographic.
4. Tell the AI what is wrong in visual terms: “the centre is losing focus,” “the edge color is uniform instead of radial,” or “the blur looks composited over a sharp image.”
5. Ask it to change only the controls necessary to address that observation and deliver a new downloadable file.
6. Tell it to preserve successful stages under new names so comparison remains possible.

## Let the AI client create and check the file

The AI client must produce the actual downloadable `.ldbpreset`; it should not give you source text that you must copy into a text editor, rename or process in Terminal. Before delivering the file, ask it to reopen its own result and check every line against the supplied schema: the format header, control names, numeric ranges, choice values, duplicate keys, dependencies and required second inputs.

That check confirms structural compatibility, not visual quality. Load the downloaded file directly in Lens Debaser, then review the result at full resolution and in motion.

## Important behaviour to tell the AI about

- **Field Shape routes other responses.** Its centre, aspect, rotation, onset and falloff may do nothing until a compatible spatial response is active.
- **Aperture & Bokeh is opt-in.** Shape, blade and cat-eye controls need Aperture Response above zero. This path is visually powerful and comparatively expensive.
- **Capture remaps active optics.** Camera format, focal length, aperture and focus distance do not constitute a complete lens effect on their own.
- **Depth Input is conditional.** A nonzero depth interpretation requires the second RGB input, and depth-aware effects still need their corresponding optical response.
- **Colour controls are not display RGB paint.** They tint a physical-effect approximation and can exceed 1.0 internally. Use restrained values first.
- **Blend is the final dry/wet mix.** Use it for overall moderation, not to compensate for a badly balanced internal response.

## Sharing presets

Use a distinctive file name and include a short comment describing intent and any required second input. Treat generated presets as starting points: the author who visually evaluates and publishes the result is responsible for its behaviour and for any reference material used while designing it.

## Version1.70 additions

Projection Model:Off/Equidistant/Stereographic; Amount0–100%, Field Angle0–89° half-diagonal, Framing:Fill Frame/Balanced/Preserve Centre Scale. Start at55° and moderate Amount. Shared Field is independent of projection angle. Effect Size defaults to Frame Relative (960×540 reference); Fixed Pixels keeps pixel radii fixed. Use the version-matched JSON schema for exact keys, ranges and current UI labels. Geometry magnification benefits from4K-or-higher source footage; a high-resolution timeline cannot restore missing detail.

## Version 1.72: Final Framing

Auto Fill Frame (`finalFramingMode=1`) crops the completed optical result to remove unwanted edge effects. It defaults to off (`0`). `finalAutoCropAdjustment` defaults to 0%, accepts −50 to +300%, and applies only with Auto Fill on; negative reduces automatic crop and positive increases it. `finalManualCrop` defaults to 0%, accepts 0 to +300%, and applies only with Auto Fill off. Keep the two settings independent. Do not use internal render-packet keys such as finalFramingZoom. Cropping changes composition and magnifies detail; insufficient source resolution can soften the result. Extreme effects can still require fine-tuning. Existing optical presets need no retuning for neutral Final Framing.
