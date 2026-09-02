# Perceptual coma and spherical-aberration model

## Research conclusion

The production-friendly pattern is a spatially varying point-spread-function
(PSF) approximation. Full prescription-based ray tracing is unnecessary for the
plugin's purpose and would conflict with its interactive performance target.

Relevant observations:

- Coma is asymmetric and field-oriented: an off-axis point becomes a comet-like
  patch with its tail directed toward or away from the optical axis.
- Primary spherical aberration is rotationally symmetric and is usefully
  represented perceptually by a soft core plus smoothly decaying halo.
- Aberrated PSFs vary across the field, so a single frame-wide convolution is
  insufficient for coma.
- Production bloom and lens-effects systems commonly extract bright energy and
  approximate convolution with bounded multi-tap or multiscale filters.

Primary references:

- Hullin et al., *Physically-Based Real-Time Lens Flare Rendering*, SIGGRAPH
  2011: https://light.informatik.uni-bonn.de/physically-based-real-time-lens-flare-rendering/
- Mahajan, *Symmetry properties of aberrated point-spread functions*, JOSA A
  1994: https://opg.optica.org/josaa/abstract.cfm?uri=josaa-11-7-1993
- Mahajan, *Imaging characteristics of Zernike and annular polynomial
  aberrations*, Applied Optics 2013:
  https://opg.optica.org/ao/abstract.cfm?uri=ao-52-10-2062
- Zheng et al., *Characterization of spatially varying aberrations for wide
  field-of-view microscopy*:
  https://pmc.ncbi.nlm.nih.gov/articles/PMC3724395/

Production implementation references:

- Arnold lens bloom uses thresholded image-space blur rather than lens-path
  simulation:
  https://help.autodesk.com/cloudhelp/ENU/AR-Core/files/ac-post-processing/arnold_user_guide_ac_lens_effects_ac_lens_bloom_html.html
- RealBloom demonstrates convolution-based aperture/halo processing:
  https://github.com/bean-mhm/realbloom/blob/main/docs/v0.7.0-beta/tutorial.md

## Implemented approximation

### Coma

- Active primarily on bright image energy.
- Strength grows quadratically away from the optical center.
- Eight samples follow an asymmetric radial tail.
- Each tail step widens tangentially to form a triangular fan rather than a
  shifted duplicate.
- The sign of `coma` reverses inward/outward tail direction.
- Energy decays along the tail.

### Spherical halo

- Active primarily on bright image energy.
- A dedicated adaptive-resolution separable Gaussian path provides a smooth,
  rotationally symmetric core and halo.
- Its threshold, radius, energy, and scratch buffers are independent from bloom
  and glare.
- The earlier twelve-tap ring approximation was rejected because point sources
  exposed its discrete sampling pattern.

### Performance behavior

Both loops are uniform conditional branches. They add no sampling cost when the
corresponding parameter is zero. They remain independent from bloom and glare,
which continue to use the adaptive-resolution scatter pipeline.

## Validation gates

- Off-axis coma must place more energy in its outward tail than inward.
- Spherical aberration must distribute smoothly decaying energy around a point
  source without discrete angular samples.
- Coma and spherical outputs must differ spatially.
- Neutral identity, alpha, working-space equivalence, M1 performance, HDR point
  sources, and real-camera images must continue to pass.
