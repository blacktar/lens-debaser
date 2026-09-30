# Alternative compound preset roadmap

The next-build expansion of Prism Refraction distribution and its validation
against the Resolve radial prism reference are specified separately in
`prism-distribution-roadmap.md`. Reassess all prism-based compound candidates
after that model work is complete.

## Evaluation

The current engine can support additional compound presets without new shader
features. The existing library already combines controls well within individual
families, but it clusters around portrait bokeh, conventional vintage primes,
anamorphic lenses and edge-stressed small formats. Several useful combinations
of prism, image circle, wear, contamination, transmission, highlight response,
variation and capture behavior remain underrepresented.

New compound presets should be authored as coherent optical ideas, not as a
competition to activate the largest number of controls. A control should be
included only when it explains a visible part of the intended result. Each
family should have a recognizable signature on both real footage and an
appropriate chart, while Medium remains a usable grading starting point.

## High-priority families possible with the current engine

### 1. Frosted Prism Portrait

Combine Prism Refraction, mild Refractive Irregularity, Front Element Wear,
Transmission, Glare/Halo and a restrained asymmetric pupil. The selected edge
would bend and separate spectrally while highlights entering that region develop
a soft veil. This is distinct from Edge Prism Glass because diffusion and
highlight contamination are the central character rather than clean refraction.

### 2. Worn Anamorphic Adapter

Combine moderate anamorphic geometry and oval bokeh with Front Element Wear,
slight decentering, field-dependent softness, uneven transmission and a
restrained flare. This would emulate an improvised or aged front anamorphic
attachment rather than a purpose-built cinema anamorphic family.

### 3. Rear-Element Haze Nocturne

Combine Internal Element Contamination, low microcontrast, spherical halo,
colored glare, coma and longitudinal color. Bright night sources would spread
through internal haze while the frame remains free of visible front-surface
marks. This uses the distinction between front wear and internal contamination
that current cinematic presets rarely foreground.

### 4. Cracked Coating Wide Angle

Combine stressed wide-angle geometry, image-circle pressure, coating wear,
cleaning marks, chromatic edge response and localized refractive irregularity.
The result should feel like an otherwise useful wide lens with damaged coatings,
not a global texture overlay.

### 5. Warm Split-Character Zoom

Combine Capture influence, breathing-style geometry, field asymmetry, variation,
warm transmission, uneven detail transfer and restrained bloom. It would provide
a more cinematic documentary zoom alternative whose character changes
coherently with the simulated focal length, aperture and focus distance.

### 6. Spectral Prism Scope

Combine a moderate anamorphic base with one-sided prism displacement, controlled
prism dispersion, oval pupil behavior and a narrow restrained streak. This is a
strong candidate for demonstrating cross-group composition, provided it remains
visibly different from both Edge Prism Glass and Electric Blue Scope.

### 7. De-centered Projection Scope

Combine projection-lens pupil irregularity and rimmed bokeh with anamorphic
aspect, shifted field center, uneven transmission, spherical halo and a small
amount of refractive anisotropy. This would produce an exotic widescreen image
without relying mainly on flare energy.

### 8. Small-Gate Dream Scope

Combine a slightly undersized anamorphic image circle, mechanical vignette,
cat-eye oval bokeh, field curvature, edge chromatic stress and soft warm
transmission. It would occupy the space between C-Mount CCTV and a conventional
anamorphic lens.

### 9. Wet Glass Memory

Combine internal cloudy contamination, broad front haze, low-frequency
refractive deformation, highlight softness, bloom and slight chromatic
asymmetry. The goal is a soft, unstable memory image with no procedural droplets
or literal dirt shapes. This avoids reviving the suspended front-dirt feature.

### 10. Surveillance IR Bloom

Combine a small image circle, hard edge pressure, monochromatic or cool-biased
transmission, clipped highlights, spherical halo, bloom, coma and coarse detail
loss. It would extend the surveillance family beyond ordinary CCTV geometry and
should be tuned on night footage with compact sources.

### 11. Antique Macro Loupe

Combine close-focus Capture behavior, strong longitudinal color, field
curvature, a rim-weighted imperfect pupil, warm density and localized spherical
halo. This would provide a tactile close-up alternative to the cleaner current
macro family.

### 12. Misaligned Telephoto Doubler

Combine a narrow protected center, decentered field, astigmatism, tangential
smear, longitudinal and lateral color, mild image-circle falloff and controlled
variation. It would emulate stacked or poorly aligned telephoto optics without
requiring a literal duplicate-image effect.

## Lower priority or blocked by the present model

- A true half-frame split diopter needs a controllable linear/curved split mask;
  the current elliptical field cannot reproduce its hard or feathered boundary
  faithfully.
- Fractal and kaleidoscopic prisms need multiple independently transformed image
  sectors; the current coherent prism is intentionally a single continuous
  wedge.
- Phantom/Spectre multi-exposure trails require temporal frame history. Current
  reflection ghosts are highlight-driven spatial responses, not motion trails.
- Swirl and semi-swirl diopters with a shaped clear center need a dedicated
  vortex-cut or spatially varying angular refraction field beyond present bokeh
  swirl.
- Literal droplets, fingerprints and cleaning smears remain deferred with the
  suspended front-dirt feature. Existing wear controls should not be stretched
  into conspicuous fake particles.

## Recommended production order

### Agreed next development milestone

The next preset-development step is to prototype these six compound families.
Prototype only Medium versions first, in this order:

1. Frosted Prism Portrait;
2. Rear-Element Haze Nocturne;
3. Worn Anamorphic Adapter;
4. Spectral Prism Scope;
5. Antique Macro Loupe;
6. Cracked Coating Wide Angle.

Evaluate each on a suitable real image and chart before authoring Subtle and
Caricature variants. Reject candidates that cannot be distinguished from an
existing family at normal viewing size. Once preset layering exists, the same
research can also yield narrow Component presets, but the initial prototypes
should remain complete Full Lens presets so their interactions are controlled
and reviewable.

This milestone begins after the 1.57 release. It does not include the blocked
split-diopter, fractal-prism, vortex-diopter or temporal-trail features, and it
does not imply an engine change unless prototype review exposes a specific
top-level model limitation.

## Acceptance criteria

- The effect reads as one optical character rather than stacked independent
  filters.
- Medium is clearly visible but suitable for real grading work.
- Subtle and Caricature are independently authored, not global scalar copies.
- The preset has an identified suitable input and an explanation of dependent
  controls.
- The result remains stable at full resolution and in Resolve thumbnails.
- It introduces no preset-specific shader branch and no measurable cost beyond
  the engine stages activated by its controls.
- The preset atlas uses an input that actually reveals its defining behavior.
