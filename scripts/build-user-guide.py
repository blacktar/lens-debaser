#!/usr/bin/env python3
"""Build the Lens Debaser HTML guide and its Resolve-style UI image source."""

from pathlib import Path
import html as html_module
import json
import plistlib

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / "docs" / "user-guide"
IMG = DOC / "images"
DOC.mkdir(parents=True, exist_ok=True)
IMG.mkdir(parents=True, exist_ok=True)
with (ROOT / "resources" / "Info.plist").open("rb") as stream:
    VERSION = plistlib.load(stream)["CFBundleShortVersionString"]
RELEASE_DATE = "2 October 2026"
RELEASE_DATE_ISO = "2026-10-02"
RELEASE_SUMMARY = "New in this release: vibe-code your own optical looks with an AI assistant using the <a href=\"#ai-presets\">included Preset Authoring Kit</a>, alongside flexible prism distribution, smoother causally ordered optics, expanded aperture and bokeh range, and clearer preset editing."

groups = [
 ("presets","Setup","Presets",[("Preset","Golden Portrait Prime — Medium","select"),("Load","Load","button"),("Save","Save","button")]),
 ("processing","Setup","Processing",[("Input Working Space","DaVinci Wide Gamut / Intermediate","select"),("Diagnostic View","Off","select")]),
 ("capture","Setup","Capture",[("Capture Influence","0.650","slider"),("Focal Length (mm)","35.0","slider"),("Aperture","2.00","slider"),("Gate / Capture Format","Super 35 24.89 × 18.66","select"),("Focus Distance (cm)","180","slider")]),
 ("look","Setup","Look",[("Character","0.350","slider"),("Vintage Bias","0.650","slider"),("Vintage Caricature","0.000","slider"),("Exotic Bias","0.000","slider"),("Classic 2x Anamorphic Bias","0.000","slider"),("Look Influence","1.000","slider")]),
 ("geometry","Optics","Geometry",[("Optical Center","X 0.500   Y 0.500","point"),("Primary Distortion","0.030","slider"),("Secondary Distortion","0.080","slider"),("Moustache","0.120","slider"),("Field-Gated Geometry","1.000","slider"),("Peripheral Stretch","0.220","slider"),("Peripheral Warp","0.180","slider")]),
 ("field-shape","Optics","Field Shape",[("Field Center","X 0.500   Y 0.500","point"),("Swirl","0.300","slider"),("Field Aspect","1.150","slider"),("Field Rotation","8.0°","slider"),("Field Onset","0.350","slider"),("Field Falloff","0.720","slider")]),
 ("focus-field","Optics","Focus & Field",[("Corner Detail Loss","0.650","slider"),("Astigmatism","0.250","slider"),("Field Curvature","0.450","slider"),("Radial Smear","0.180","slider"),("Tangential Smear","0.280","slider")]),
 ("detail","Optics","Detail Transfer",[("Microcontrast","−0.250","slider"),("Fine Detail","−0.150","slider"),("Edge Falloff","0.550","slider"),("Sagittal Detail","0.200","slider"),("Tangential Detail","−0.180","slider"),("Detail Scale","2.000","slider")]),
 ("chromatic","Optics","Chromatic Aberration",[("Red Fringing","0.650","slider"),("Blue Fringing","−0.850","slider"),("Chromatic Onset","−1.000","slider"),("Chromatic Falloff","1.000","slider-disabled"),("Longitudinal Amount","0.300","slider"),("Longitudinal Radius","4.00","slider"),("Near-Focus Color","","color"),("Far-Focus Color","","color")]),
 ("anamorphic","Optics","Anamorphic",[("Anamorphic Field","1.300","slider"),("Distortion","0.025","slider"),("Aberration","0.550","slider"),("Flare Amount","0.650","slider"),("Flare Radius","145","slider"),("Flare Thickness","1.000","slider"),("Vertical Rays","0.350","slider"),("Ray Length","180","slider"),("Flare Threshold","0.800","slider"),("Flare Core","0.350","slider"),("Flare Asymmetry","0.080","slider"),("Ghost Amount","0.075","slider"),("Ghost Position","−0.720","slider"),("Ghost Scale","1.000","slider"),("Ghost Paths","3","slider"),("Ghost Spacing","90","slider"),("Ghost Size Decay","0.820","slider"),("Ghost Energy Decay","0.620","slider"),("Flare Bands","0.680","slider"),("Band Separation","34","slider"),("Secondary Streak","0.340","slider"),("Secondary Offset","230","slider"),("Flare Color","","color"),("Ghost Color","","color")]),
 ("refractive","Optics","Refractive Irregularity",[("Irregularity Amount","0.650","slider"),("Irregularity Scale","1.400","slider"),("Edge Bias","0.550","slider"),("Directionality","0.350","slider"),("Direction","18.0°","slider"),("Irregular Dispersion","0.280","slider"),("Irregularity Seed","27182","slider")]),
 ("prism","Optics","Prism Refraction",[("Prism Distribution","Radial Field","select"),("Prism Amount","0.720","slider"),("Prism Direction","0.0°","slider"),("Prism Dispersion","0.580","slider"),("Prism Edge Bias","0.500","slider-disabled"),("Prism Softness","0.380","slider-disabled")]),
 ("aperture","Pupil & Vignette","Aperture & Bokeh",[("Aperture Response","0.650","slider"),("Aperture Shape","Oval / Anamorphic","select"),("Response Radius","15.00","slider"),("Blade Count","6","slider-disabled"),("Blade Curvature","0.500","slider-disabled"),("Aperture Rotation","0.0","slider"),("Edge Softness","0.500","slider"),("Cat-Eye","0.500","slider"),("Pupil Aspect","2.000","slider"),("Bokeh Swirl","2.500","slider"),("Pupil Shift","0.250","slider"),("Pupil Clipping","0.350","slider"),("Pupil Rim Weight","0.200","slider")]),
 ("vignette","Pupil & Vignette","Vignette",[("Natural Vignette","0.000","slider"),("Optical Vignette","0.180","slider"),("Mechanical Vignette","0.000","slider")]),
 ("image-circle","Pupil & Vignette","Image Circle",[("Image Circle Size","1.200","slider"),("Image Circle Aspect","1.000","slider"),("Image Circle Softness","0.100","slider")]),
 ("bloom","Light","Bloom",[("Bloom Amount","0.450","slider"),("Bloom Threshold","0.700","slider"),("Bloom Radius","52.0","slider"),("Bloom Stretch","1.800","slider")]),
 ("glare-halo","Light","Glare & Halo",[("Spherical Halo","0.350","slider"),("Glare Amount","0.320","slider"),("Glare Threshold","0.450","slider"),("Glare Radius","58.0","slider"),("Glare Color Amount","0.180","slider"),("Glare Color","","color")]),
 ("transmission","Light","Transmission",[("Transmission Amount","0.280","slider"),("Transmission Density","0.180","slider"),("Transmission Contrast","−0.220","slider"),("Highlight Softness","0.550","slider"),("Transmission Color","","color")]),
 ("highlight-response","Light","Highlight Response",[("Highlight Knee","0.700","slider")]),
 ("off-axis","Advanced","Off-Axis Character",[("Coma","0.280","slider"),("Coma Threshold","0.500","slider")]),
 ("variation","Advanced","Variation",[("Variation Amount","0.650","slider"),("Variation Seed","27183","slider"),("Field Asymmetry","0.350","slider"),("Pupil Irregularity","0.420","slider"),("Chromatic Asymmetry","0.550","slider"),("Transmission Unevenness","0.300","slider")]),
 ("front-wear","Advanced","Front Element Wear",[("Cleaning Haze","0.650","slider"),("Cleaning Marks","0.800","slider"),("Deep Scratches","0.550","slider"),("Scratch Direction","28.0°","slider"),("Mark Scale","1.250","slider"),("Coating Wear","0.700","slider"),("Wear Patch Scale","1.400","slider"),("Damage Seed","31415","slider")]),
 ("internal-contamination","Advanced","Internal Element Contamination",[("Internal Dirt Amount","1.200","slider"),("Internal Dirt Size","1.450","slider"),("Internal Smear","0.350","slider"),("Internal Scatter","1.000","slider"),("Cloud Softness","0.650","slider"),("Cloud Complexity","0.450","slider"),("Internal Dirt Seed","16180","slider")]),
 ("depth","Advanced","Depth Input",[("Depth Interpretation","Near Black","select"),("Input Near","0.000","slider"),("Input Far","1.000","slider"),("Focus Depth","0.500","slider"),("Defocus Onset","0.080","slider"),("Defocus Falloff","0.520","slider"),("Depth Edge Protection","1.000","slider"),("Depth Edge Softness","0.500","slider")]),
 ("blend","Blend","Blend",[("Blend","1.000","slider")]),
]

descriptions = {
"presets":("Load, select and save Lens Debaser presets.","Load opens a .ldbpreset file and adds the presets in its folder to the Preset menu. Choose a name from the menu to apply it. After you adjust a loaded preset, its name remains visible with an asterisk prefix so you retain the starting-point reference; returning every control to the loaded values removes the asterisk. Custom is reserved for settings that are not based on a loaded preset. Save writes the visible lens settings to a new .ldbpreset file."),
"processing":("Define the color encoding entering the node and temporarily inspect individual processing stages.","Input Working Space tells Lens Debaser how to decode the incoming RGB values. The plugin converts that input to linear AP1, performs its optical processing there, then returns the result to the selected working space so it remains correctly placed in the Resolve color pipeline. Choose the space of the image entering this node—not the timeline or delivery space unless they are also the node input. A wrong selection changes luminance, color, thresholds and therefore the behavior of bloom, flare, transmission and other effects. Diagnostic View temporarily replaces the normal result with an analysis image; it does not change the preset or create a finishing look. Keep Diagnostic View set to Off for normal work."),
"capture":("Make compatible lens effects respond together to focal length, aperture, focus distance and capture format.","Capture does not add a visible effect by itself. Instead, it modifies compatible controls that are already active elsewhere in Lens Debaser. A wider field of view—produced by a shorter focal length or a larger capture gate—strengthens off-axis effects such as distortion, lateral color fringing, edge softness, field curvature, directional smear and natural falloff. A larger aperture, shown by a smaller f-number, strengthens pupil-related effects such as coma, optical vignetting, aperture-shaped defocus and anamorphic flare. Closer focus strengthens spherical softness, aperture-shaped defocus and longitudinal focus color. Capture Influence sets how strongly these relationships affect the active controls; at zero, the focal length, aperture, focus distance and gate settings make no change."),
"look":("Quickly steer the image toward a broad lens character before fine-tuning individual controls.","Character adds a restrained mix of softness, edge color, falloff and highlight response. Vintage Bias produces a warmer, softer and less corrected image; Vintage Caricature pushes that treatment further. Exotic Bias favors irregular distortion, color separation and asymmetry. Classic 2x Anamorphic Bias introduces oval bokeh, cylindrical edge behavior and horizontal flare character. The biases can be combined, and Look Influence controls their overall strength."),
"geometry":("Model conventional distortion and gradual optical edge deformation around an adjustable center.","Primary Distortion handles the broad bend, Secondary adds higher-order curvature, and Moustache creates a direction-changing wave. Field-Gated Geometry applies the Field Shape envelope to geometry; Peripheral Stretch adds smooth edge magnification and Peripheral Warp adds nonuniform bending rather than another barrel-distortion term."),
"field-shape":("Choose where edge-dependent lens effects begin and how they spread across the frame.","Field Center moves the best-corrected area. Field Aspect and Rotation stretch and turn the affected region, while Swirl rotates image structure around it. Field Onset sets how much of the center remains protected; Field Falloff controls whether the transition toward the edges is gradual or concentrated. This shared spatial group shapes geometry, focus, chromatic, prism and pupil responses, so Lens Debaser keeps it open when presets are loaded. It needs at least one downstream effect to produce a visible change."),
"focus-field":("Keep one area relatively clear while focus and detail become less uniform toward the edges.","Corner Detail Loss softens outer detail. Field Curvature makes the apparent focus plane bow across the frame. Astigmatism changes radial and circular detail differently, while Radial and Tangential Smear pull soft detail in those respective directions. Field Shape determines where these changes begin."),
"detail":("Change the texture and crispness of the image at broad, fine and directional scales.","Microcontrast changes local separation in medium-sized detail. Fine Detail changes smaller texture. Edge Falloff lets detail weaken away from the center. Sagittal and Tangential Detail independently affect lines running toward the image center and lines running around it, while Detail Scale chooses the size of structure being affected."),
"chromatic":("Add lateral edge separation and depth-sensitive longitudinal color fringing.","Red and Blue Fringing respond most visibly to high-contrast edges and increase away from the optical center. Chromatic Onset at −1 follows the shared Field envelope; values from 0 upward enable an independent onset and falloff. Longitudinal Amount and Radius tint the soft side of focus transitions with the selected near/far colors; fine edges, specular detail and a depth map make this response easiest to see."),
"anamorphic":("Create the stretched geometry, edge color and horizontal flare behavior associated with anamorphic lenses.","Anamorphic Field controls the overall cylindrical character. Distortion bends geometry differently across the horizontal and vertical axes, while Aberration adds directionally stretched color separation. Flare Amount, Radius and Thickness create the main horizontal streak; Bands and Secondary Streak add layered structure. Vertical Rays create a cross-like highlight response, and Ghost controls add a sequence of softer colored reflections across the frame. Threshold determines which highlights are bright enough to produce these effects."),
"refractive":("Add gentle waves, local stretching and color shifts that suggest uneven or stressed glass.","Amount controls the strength and Scale controls the size of the warped regions. Edge Bias confines more of the effect to the outer frame. Directionality, Direction and Rotation stretch and orient the pattern. Irregular Dispersion adds a small color split to the warped detail, and Seed chooses another repeatable pattern."),
"prism":("Create coherent glass-like displacement and spectral separation across a selectable part of the image.","Distribution selects a one-sided Linear Edge, a full-frame Uniform response, a symmetric Bilateral axis, an outward Radial Field, or an Inverse Field concentrated around the center. Amount controls displacement and Dispersion separates color along the same optical path. Direction sets the refraction axis, or rotates the local direction in Radial Field mode. Bilateral, Radial and Inverse modes follow Field Center, Aspect, Rotation, Onset and Falloff. Edge Bias and Softness apply only to Linear Edge."),
"aperture":("Shape the appearance of defocused highlights and peripheral bokeh.","Aperture Response is the opt-in control for shaped bokeh. At zero, the aperture reconstruction stage is bypassed and the dependent pupil controls are disabled; choosing a shape alone does not activate the effect. Increase Response to mix the selected pupil shape into ordinary defocus, then use Response Radius—up to 48 pixels—to set its size. Shape, 3–16 polygon blades, curvature, rotation, softness and Pupil Aspect—up to 8×—define the highlight silhouette; higher blade counts approach the separate Circular shape. Cat-Eye compresses bokeh near the frame edge. Bokeh Swirl progressively stretches and turns the off-axis pupil around the Field Center across its 0–12 range. Pupil Shift and Clipping make edge bokeh close unevenly, while Rim Weight creates a brighter outer ring. Aperture/bokeh presets expose Field Shape and Focus & Field because those groups control where the response develops and can further reshape it. These controls are easiest to judge on small background lights or specular highlights that are out of focus."),
"vignette":("Combine three distinct forms of edge attenuation.","Natural is smooth illumination falloff, Optical is pupil/field shading, and Mechanical is a harder obstruction-like cutoff."),
"image-circle":("Define the lens-coverage boundary used by Mechanical Vignette.","Size controls coverage, Aspect makes it elliptical and Softness controls the boundary transition. These controls have no visible effect while Mechanical Vignette is zero."),
"bloom":("Spread highlight energy into a soft luminous neighborhood.","Amount is energy, Threshold chooses qualifying scene-linear highlights, Radius sets reach, and Bloom Stretch makes the spread directional. Lamps, reflections, bright windows and overexposed edges produce the clearest response; a low-dynamic-range or dim input may show little change until Threshold is lowered."),
"glare-halo":("Add broad veiling glare or a tighter spherical glow around highlights.","Glare spreads qualifying highlights into a wide, smooth veil. Amount sets its strength, Glare Threshold chooses which highlights feed it, Radius sets its reach, and the color controls tint only the glare contribution. Spherical Halo creates a more concentrated glow immediately around bright detail. The two responses can be used separately or together. Lamps, reflections and bright windows against darker surroundings show them most clearly. Glare has its own threshold and does not depend on Bloom."),
"transmission":("Simulate color and tonal behavior caused by glass and coatings.","Transmission Amount mixes the selected transmission color. Density, Contrast and Highlight Softness shape light passage without requiring bloom or glare."),
"highlight-response":("Control how smoothly bright areas begin to produce glow, flare and other highlight effects.","Highlight Knee changes the transition around the thresholds used by Bloom, Glare, Spherical Halo, Coma and Anamorphic Flare. A harder knee limits the response more tightly to the brightest values; a softer knee brings surrounding highlight detail into the effect more gradually. It has no visible result until at least one of those highlight effects is active."),
"off-axis":("Create asymmetric, field-dependent highlight tails.","Coma sets tail strength and direction; its sign swaps orientation. Coma Threshold is the scene-linear highlight level at which the response begins. The response is clearest on isolated bright points away from the Field Center and may be inconspicuous on evenly lit or low-contrast material."),
"variation":("Make an otherwise clean lens treatment feel less perfectly centered and manufactured.","Variation Amount controls the overall strength. Field Asymmetry shifts edge behavior, Pupil Irregularity changes bokeh, Chromatic Asymmetry makes color fringing less even, and Transmission Unevenness introduces subtle tonal variation. Seed chooses another repeatable version. These controls vary effects that are already active, so a compatible field, aperture, chromatic or transmission setting is required."),
"front-wear":("Add the softened contrast, flare and fixed marks associated with a worn front element.","Cleaning Haze lowers contrast around light. Cleaning Marks and Deep Scratches become most visible when bright windows or practicals illuminate them; Direction and Mark Scale set their orientation and size. Coating Wear introduces patchy shifts in contrast, color and flare. Damage Seed chooses another repeatable wear pattern."),
"internal-contamination":("Introduce broad cloudy density, smearing and veiling from contamination inside the lens.","Amount controls the overall visibility and Size sets the scale of the cloudy regions. Smear stretches them, Scatter increases localized glow and loss of contrast, Softness smooths their boundaries, and Complexity adds overlapping large-scale variation. Bright windows and practical lights make the scatter easiest to see. Seed chooses another repeatable pattern."),
"depth":("Use a depth map to place focus and control depth-aware optical effects.","Lens Debaser reads a grayscale depth image through its Second RGB/Depth Map input. The depth signal controls where enabled focus, aperture, halo and other depth-aware responses appear; it does not create an optical look until compatible effects are active."),
"blend":("Mix the complete processed result with the untouched source.","Blend 0 is the input image; Blend 1 is the full effect. It remains the final control group for predictable finishing."),
}

lens = [
("Golden Portrait Prime","Warm dimensional portrait rendering with a protected center, curved edge falloff and highlight-sensitive glare."),
("Silver Contrast Prime","Cooler, lower-contrast still-glass character with organic edge loss and restrained axial color."),
("Uncoated Newsreel","Warm uncoated transmission, reduced contrast, haze, bloom and glare that respond strongly to windows and practicals."),
("Breathing Documentary Zoom","Soft vintage zoom character with gradual edge geometry, uneven field response and chromatic texture."),
("Rotating Bokeh Portrait","Tangentially stretched peripheral bokeh around a usable portrait center; small bright background points reveal it best."),
("Petzval Oval Portrait","Warm oval-pupil portrait response with curved focus, cat-eye deformation and asymmetric historical character."),
("Bubble Bokeh Triplet","Firm round defocus highlights, curved edge focus and visible longitudinal color around bright background points."),
("Pearlescent Diffusion","Dreamy soft-focus response with spherical halo, bloom, glare and reduced microcontrast while retaining a usable center."),
("Electric Blue Scope","Two-times anamorphic field with oval bokeh, edge aberration and strong blue streak response above the flare threshold."),
("Honeyed Compact Scope","Warm compact anamorphic character with elliptical falloff, amber streaks and restrained edge softness."),
("Bent Glass Scope","Pronounced off-axis anamorphic deformation, refractive irregularity, directional focus loss and chromatic separation."),
("Neon Radiance Prime","Clean center with conspicuous colored highlight radiance; lamps, signs, reflections and windows drive the effect."),
("Nocturnal Cat-Eye","Strong off-axis pupil deformation, curved focus, coma and axial color; requires isolated peripheral highlights."),
("Stressed Ultra Wide","Gradual peripheral stretch and warp, complex moustache geometry and heavy edge chromatic aberration."),
("Rehoused Still Glass","Repeatable decentering, refractive unevenness and coating wear with a restrained photographic base."),
("C-Mount CCTV","Small-image-circle coverage, hard mechanical vignette, heavy edge softness, coma and chromatic stress."),
("Close Focus Macro","Close-focus spherical and longitudinal aberration with a deliberately retained in-focus region."),
("Microscope Objective","Tight central correction surrounded by rapid field curvature, edge softness and chromatic separation."),
("Tilted Freelens","Strong asymmetric focus plane, directional smear and irregular off-axis rendering."),
("Improvised Projector Lens","Unconventional pupil, glow, aberration and refractive behavior inspired by adapted projection optics."),
("Bodycam Edge Stress","Single signature preset with hard image-circle coverage, spherical edge defocus, gradual edge CA and refractive distortion."),
("Hawk V-Lite Vintage '74","Inspired by an anamorphic profile with oval off-axis bokeh, vintage field softness, broad blue flare and a structured reflection train."),
("Cooke Anamorphic /i Special Flare","Inspired by an anamorphic profile with blue-cyan streaks, smooth vertical diffraction, controlled wash and focal-length-aware flare structure."),
("Decentered Dream Glass","Creative compound optic combining pupil decentering, clipping, field asymmetry, refractive irregularity and soft highlight response."),
("Edge Prism Glass","Hand-held linear-prism character with a smooth one-sided bend, controlled spectral separation and softly integrated edge stress."),
("Internal Field Edge FX","Protected elliptical centre with smooth peripheral lens blur and restrained purple/green edge separation, using Lens Debaser's internal field rather than a depth input."),
]

root_descriptions = {
"Setup":"Choose presets, define input interpretation, and apply broad capture and look behavior.",
"Optics":"Shape geometry, the optical field, focus transfer, detail, chromatic, anamorphic, refractive and prism behavior.",
"Pupil & Vignette":"Control the aperture footprint, illumination falloff and the lens image-circle boundary.",
"Light":"Model highlight bloom, glare, spherical halos and the tonal or color response of glass transmission.",
"Advanced":"Refine off-axis behavior, repeatable lens variation, element wear, internal contamination and depth-aware processing.",
"Blend":"Set the final mix between the original image and the complete processed result.",
}

def ui_card(slug,root,title,controls):
    rows=[]
    for label,value,kind in controls:
        if kind in ("slider", "slider-disabled"):
            content=f'<span class="track"><i></i></span><span class="value">{value}</span>'
        elif kind=="button":
            content=f'<span class="button">{value}</span>'
        elif kind=="select":
            content=f'<span class="select"><span>{value}</span><span>⌄</span></span>'
        elif kind=="color":
            content='<span class="color-control"><span class="swatch"></span><span class="pipette">⌁</span></span>'
        else:
            content=f'<span class="point">{value}</span>'
        rows.append(f'<div class="row {kind}"><span class="label">{label}</span>{content}</div>')
    child = "" if root == title else f'<h3>▾ {title}</h3>'
    return f'<article class="panel" id="{slug}"><div class="section"><h2>▾ {root}</h2>{child}{"".join(rows)}</div></article>'

css="""
*{box-sizing:border-box}html,body{margin:0;background:#25282c;color:#d9dcdf;font:14px -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif}.gallery{width:520px;margin:0}.gallery:has(.panel:target) .panel{display:none}.gallery .panel:target{display:block!important}.panel{width:520px;background:#25282c}.section h2,.section h3{height:38px;display:flex;align-items:center;margin:0;padding:0 14px;border-bottom:1px solid #181a1d;font-size:12px;letter-spacing:.1em}.section h2{background:#35393d;text-transform:uppercase}.section h3{padding-left:28px;background:#2d3033;color:#d2d5d8}.row{height:39px;display:grid;grid-template-columns:170px 1fr 74px;gap:10px;align-items:center;padding:4px 14px;border-top:1px solid #303338}.label{color:#c5c8cb;text-align:right}.track{height:2px;background:#80858a;position:relative}.track i{position:absolute;width:12px;height:12px;border-radius:50%;background:#b9bec3;left:57%;top:-5px}.value,.point{background:#181a1d;border:1px solid #4b5055;padding:5px 8px;text-align:right}.select,.button,.point{grid-column:2/4}.select{display:flex;justify-content:space-between;background:#1a1c1f;border:1px solid #555a60;padding:5px 9px}.button{text-align:center;background:#3c4045;border:1px solid #555a60;padding:5px 9px}.color-control{grid-column:2/4;display:flex;align-items:center;gap:9px}.swatch{width:36px;height:19px;background:#fff;border:1px solid #8d9297}.pipette{font-size:20px;color:#d7dadd;transform:rotate(-45deg);display:inline-block}.point{text-align:left}.slider-disabled{opacity:.35}
"""
mock=f'<!doctype html><html><head><meta charset="utf-8"><style>{css}</style></head><body><main class="gallery">'+''.join(ui_card(*g) for g in groups)+'</main></body></html>'
(DOC/'ui-source.html').write_text(mock)

def image_uri(slug):
    # Control groups are rendered as deterministic documentation artwork from
    # the same inventory used to write the guide. They intentionally resemble
    # Resolve's Inspector layout but are labelled as illustrations, never as
    # literal host screenshots.
    matching = next((group for group in groups if group[0] == slug), None)
    if matching:
        _, root, title, controls = matching
        row_height = 39
        header_count = 1 if root == title else 2
        height = header_count * 38 + len(controls) * row_height
        pieces = [f'<svg xmlns="http://www.w3.org/2000/svg" width="520" height="{height}" viewBox="0 0 520 {height}">',
                  '<rect width="520" height="100%" fill="#25282c"/>']
        y = 0
        for heading, fill, x in ((root.upper(), '#35393d', 14),):
            pieces += [f'<rect y="{y}" width="520" height="38" fill="{fill}"/>',
                       f'<text x="{x}" y="24" fill="#d9dcdf" font-family="-apple-system,Segoe UI,sans-serif" font-size="12" font-weight="700" letter-spacing="1.2">▼ {html_module.escape(heading)}</text>']
            y += 38
        if root != title:
            pieces += [f'<rect y="{y}" width="520" height="38" fill="#2d3033"/>',
                       f'<text x="28" y="{y+24}" fill="#d2d5d8" font-family="-apple-system,Segoe UI,sans-serif" font-size="12" font-weight="700">▼ {html_module.escape(title)}</text>']
            y += 38
        for label, value, kind in controls:
            pieces += [f'<line x1="0" y1="{y}" x2="520" y2="{y}" stroke="#303338"/>',
                       f'<text x="170" y="{y+25}" text-anchor="end" fill="#c5c8cb" font-family="-apple-system,Segoe UI,sans-serif" font-size="14">{html_module.escape(label)}</text>']
            if kind.startswith('slider'):
                opacity = '.35' if kind == 'slider-disabled' else '1'
                pieces += [f'<line x1="190" y1="{y+20}" x2="405" y2="{y+20}" stroke="#80858a" stroke-width="2" opacity="{opacity}"/>',
                           f'<circle cx="313" cy="{y+20}" r="6" fill="#b9bec3" opacity="{opacity}"/>',
                           f'<rect x="429" y="{y+7}" width="74" height="25" fill="#181a1d" stroke="#4b5055" opacity="{opacity}"/>',
                           f'<text x="493" y="{y+25}" text-anchor="end" fill="#d9dcdf" font-family="-apple-system,Segoe UI,sans-serif" font-size="13" opacity="{opacity}">{html_module.escape(value)}</text>']
            elif kind == 'color':
                pieces += [f'<rect x="190" y="{y+10}" width="36" height="19" fill="#fff" stroke="#8d9297"/>']
            else:
                pieces += [f'<rect x="190" y="{y+7}" width="313" height="25" fill="#181a1d" stroke="#555a60"/>',
                           f'<text x="200" y="{y+25}" fill="#d9dcdf" font-family="-apple-system,Segoe UI,sans-serif" font-size="13">{html_module.escape(value)}</text>']
            y += row_height
        pieces.append('</svg>')
        controls_dir = IMG / "controls"
        controls_dir.mkdir(parents=True, exist_ok=True)
        control_path = controls_dir / f"{slug}.svg"
        control_path.write_text(''.join(pieces))
        return f"images/controls/{slug}.svg"
    p=IMG/f"{slug}.webp"
    if p.exists(): return f"images/{slug}.webp"
    return f"images/{slug}.webp"

def guide_example_uri(filename):
    path = IMG / "examples" / filename
    if path.exists(): return f"images/examples/{filename}"
    pending = IMG / "examples" / "render-pending.svg"
    pending.parent.mkdir(parents=True, exist_ok=True)
    if not pending.exists():
        pending.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="960" height="540"><rect width="100%" height="100%" fill="#181b1e"/><text x="50%" y="50%" text-anchor="middle" fill="#aab1b6" font-family="sans-serif" font-size="28">Render pending: make guide-examples</text></svg>')
    return "images/examples/render-pending.svg"

IPHONE_CAPTURE="color-graded image captured with an iPhone 17 Pro and a 1.55× anamorphic adapter (ProRes RAW Open Gate)"
example_specs = [
 ("presets","Presets","milano1",f"Image 1 · {IPHONE_CAPTURE}","A preset recalls a complete set of Lens Debaser controls. This example uses Demo Look to make a clearly visible starting treatment that can then be refined for the shot."),
 ("processing","Diagnostic Views","iso","ISO 12233 chart","This single comparison demonstrates Diagnostic View → Difference (Amplified): Detail Transfer is deliberately enabled, and the applied side replaces the normal image with an amplified map of where Lens Debaser changes it. Neutral grey means little or no change; brighter, darker or colored regions identify altered image structure. Set Diagnostic View back to Off to see the finished image."),
 ("capture","Capture","iso","ISO 12233 chart","Demo Capture supplies four direct image effects: peripheral detail loss, field curvature, longitudinal focus color and natural vignetting. Capture then coordinates their strength from the simulated shooting setup. Its 24 mm focal length on a Super 35 gate produces a sufficiently wide field of view to strengthen off-axis softness, curvature and falloff; its f/1.6 aperture and 90 cm focus distance strengthen the defocus and longitudinal color response. The applied image therefore shows the preset's four effects after Capture has modified them—not an effect created by Capture alone."),
 ("look","Look","milano2",f"Image 2 · {IPHONE_CAPTURE}","The applied image combines softer detail, warmer transmission, stronger edge falloff, color fringing and less even correction. Adjust the individual Look biases to move from restrained character toward vintage, exotic or anamorphic rendering."),
 ("geometry","Geometry","optical","Lens Debaser synthetic optical chart","Straight lines expose primary, secondary and moustache distortion; the shared Field envelope controls their gradual onset."),
 ("field-shape","Field Shape","iso","ISO 12233 chart","Field Shape determines where edge-dependent changes begin. The preset adds focus loss, directional softness and color fringing so moving the center, stretching or rotating the field, and changing onset or falloff can be seen directly."),
 ("focus-field","Focus & Field","iso","ISO 12233 chart","The center remains relatively clear while fine structure becomes softer, curved and directionally smeared toward the frame edges."),
 ("detail","Detail Transfer","iso","ISO 12233 chart","The applied image reduces broad local contrast and fine texture, weakens detail near the edges and treats radial and circular line detail differently."),
 ("chromatic","Chromatic Aberration","iso","ISO 12233 chart","High-contrast outer edges reveal lateral red/blue separation. Longitudinal color becomes most informative with depth or defocused highlights."),
 ("anamorphic","Anamorphic","milano1",f"Image 1 · {IPHONE_CAPTURE}","Architectural lines reveal cylindrical geometry while the repeated practical lights provide real scene highlights for the anamorphic flare response."),
 ("refractive","Refractive Irregularity","optical","Lens Debaser synthetic optical chart","The applied image adds repeatable local ripples and slight color shifts, most easily seen in straight lines and fine detail toward the edges."),
 ("prism","Prism Refraction","optical","Lens Debaser synthetic optical chart","The applied image uses Radial Field distribution to bend detail outward from a wide elliptical center and adds controlled spectral separation along each local refraction direction."),
 ("aperture","Aperture & Bokeh","milano1",f"Image 1 · {IPHONE_CAPTURE}","The preset turns blurred highlights into a softly rounded seven-blade shape, compresses them toward the frame edge and adds a gentle rotational change around the center. Sharp areas mainly show the accompanying focus transfer."),
 ("vignette","Vignette","optical","Lens Debaser synthetic optical chart","An evenly exposed chart separates gradual natural and optical shading from harder mechanical obstruction."),
 ("image-circle","Image Circle","optical","Lens Debaser synthetic optical chart","Image Circle defines a boundary but does nothing by itself. Mechanical Vignette is enabled so size, aspect and softness can shape coverage."),
 ("bloom","Bloom","milano2",f"Image 2 · {IPHONE_CAPTURE}","Bloom needs pixels above its scene-linear threshold. The bright exterior and ceiling practicals reveal amount, radius and stretch on real material."),
 ("glare-halo","Glare & Halo","milano3",f"Image 3 · {IPHONE_CAPTURE}","The preset combines a wide warm glare veil with a tighter spherical glow. Bright windows and practical lights against darker surroundings reveal the difference between the two responses."),
 ("transmission","Transmission","milano3",f"Image 3 · {IPHONE_CAPTURE}","Real tonal and color variation reveals glass color, density, contrast and highlight softness more clearly than a binary chart."),
 ("highlight-response","Highlight Response","milano2",f"Image 2 · {IPHONE_CAPTURE}","Highlight Response does nothing alone, so the preset enables bloom, glare, coma, halo and flare. Highlight Knee controls how abruptly those enabled effects build around their own thresholds, changing the transition without replacing their individual Threshold controls."),
 ("off-axis","Off-Axis Character","milano1",f"Image 1 · {IPHONE_CAPTURE}","Coma needs bright points above its threshold and becomes strongest away from Field Center. The repeated lamps provide real off-axis sources."),
 ("variation","Variation","iso","ISO 12233 chart","Variation does nothing to a completely neutral lens, so the preset first enables field, bokeh, color-fringing and transmission behavior. Variation then makes those changes less centered and uniform."),
 ("front-wear","Front Element Wear","milano1",f"Image 1 · {IPHONE_CAPTURE}","The applied image combines lower contrast around light, repeatable cleaning and scratch marks, and patchy coating-related color and contrast changes."),
 ("internal-contamination","Internal Element Contamination","milano2",f"Image 2 · {IPHONE_CAPTURE}","The applied image gains broad cloudy density variation, elongated soft patches and localized veiling around brighter parts of the frame."),
 ("depth","Depth Input","depth","Synthetic scene with embedded depth","Depth controls require a second depth signal. Aperture defocus and halo are enabled so focus placement, defocus response and edge protection become visible without adding a color cast."),
]
atlas_sources=[("iso","ISO 12233 chart"),("optical","Lens Debaser synthetic optical chart"),("milano1",f"Image 1 · {IPHONE_CAPTURE}"),("milano2",f"Image 2 · {IPHONE_CAPTURE}"),("milano3",f"Image 3 · {IPHONE_CAPTURE}")]
example_demo_numbers={
 "presets":2,"processing":6,"capture":1,"look":2,"geometry":3,"field-shape":4,
 "focus-field":5,"detail":6,"chromatic":7,"anamorphic":8,"refractive":21,"prism":31,"aperture":9,
 "vignette":10,"image-circle":11,"bloom":12,"glare-halo":13,"transmission":14,
 "highlight-response":15,"off-axis":16,"variation":17,"front-wear":20,
 "internal-contamination":24,"depth":18,
}
example_cards=[]
for slug,title,_preferred_source,_source_label,note in example_specs:
    comparisons=[]
    sources_for_group=atlas_sources[:1] if slug == 'processing' else atlas_sources
    for source,source_name in sources_for_group:
        before=guide_example_uri(f"{source}-before.png"); after=guide_example_uri(f"{slug}-{source}-after.png")
        after_label='Difference diagnostic' if slug == 'processing' else 'Applied'
        media_aspect='4224/2000' if source.startswith('milano') else '16/9'
        comparisons.append(f'''<figure class="image-compare" data-compare style="--split:50%;--split-number:50;--media-aspect:{media_aspect}"><img src="{after}" alt="{title} applied to {source_name}" loading="lazy" decoding="async"><div class="before-layer"><img src="{before}" alt="Neutral {source_name} before {title}" loading="lazy" decoding="async"></div><span class="compare-divider" aria-hidden="true"></span><span class="compare-label before-label">Before</span><span class="compare-label after-label">{after_label}</span><input type="range" min="0" max="100" value="50" aria-label="Compare neutral and {title} applied to {source_name}"></figure>''')
    preset_number=example_demo_numbers[slug]
    matches=sorted((ROOT / "presets" / "demonstrations").glob(f"{preset_number:02d}-Demo-*.ldbpreset"))
    preset_name=matches[0].stem if matches else f"{preset_number:02d}-Demo preset"
    preset_used=f'<p class="applied-recipe"><b>Applied preset for the comparisons below:</b> <code>{preset_name}</code></p>'
    example_cards.append(f'''<section class="example-card" id="example-{slug}"><div><h3>{title}</h3><p class="section-jump"><a href="#{slug}">Reference ↑</a></p><p>{note}</p>{preset_used}</div><div class="example-gallery">{''.join(comparisons)}</div></section>''')
examples_html=f'''<article id="control-examples" class="examples-intro"><p class="eyebrow">INTERACTIVE OPTICAL ATLAS</p><h2>See the optical control groups in action</h2><p class="lead">Optical groups are shown on both charts and three color-graded images captured with an iPhone 17 Pro and a 1.55× anamorphic adapter (ProRes RAW Open Gate), rendered by the current Lens Debaser engine. Processing uses one focused diagnostic example.</p></article>{''.join(example_cards)}'''

def guide_file_slug(value):
    result=[]
    separator=False
    for character in value.lower():
        if character.isalnum():
            if separator and result:
                result.append('-')
            result.append(character)
            separator=False
        else:
            separator=True
    return ''.join(result)

preset_cards=[]
medium_presets=sorted((ROOT / "presets" / "cinematic-lenses").glob("*-2-Medium.ldbpreset"))
medium_presets.append(ROOT / "presets" / "cinematic-lenses" / "21-Bodycam-Edge-Stress.ldbpreset")
medium_presets.append(ROOT / "presets" / "cinematic-lenses" / "26-Internal-Field-Edge-FX.ldbpreset")
medium_presets.sort()
for preset_path in medium_presets:
    preset_name=preset_path.stem
    family_number=int(preset_name.split('-',1)[0])
    family,description=lens[family_number-1]
    preset_slug=guide_file_slug(preset_name)
    comparisons=[]
    for source,source_name in atlas_sources:
        before=guide_example_uri(f"{source}-before.png")
        after=guide_example_uri(f"preset-{preset_slug}-{source}-after.png")
        media_aspect='4224/2000' if source.startswith('milano') else '16/9'
        comparisons.append(f'''<figure class="image-compare" data-compare style="--split:50%;--split-number:50;--media-aspect:{media_aspect}"><img src="{after}" alt="{preset_name} applied to {source_name}" loading="lazy" decoding="async"><div class="before-layer"><img src="{before}" alt="Neutral {source_name} before {preset_name}" loading="lazy" decoding="async"></div><span class="compare-divider" aria-hidden="true"></span><span class="compare-label before-label">Before</span><span class="compare-label after-label">Applied</span><input type="range" min="0" max="100" value="50" aria-label="Compare neutral and {preset_name} applied to {source_name}"></figure>''')
    preset_cards.append(f'''<section class="example-card" id="preset-example-{preset_slug}"><div><h3>{family}</h3><p>{description}</p><p class="applied-recipe"><b>Applied preset for the comparisons below:</b> <code>{preset_name}</code></p></div><div class="example-gallery">{''.join(comparisons)}</div></section>''')
preset_examples_html=f'''<article id="preset-examples" class="examples-intro"><p class="eyebrow">PRESET ATLAS</p><h2>See the included presets in action</h2><p class="lead">Each cinematic-lens family is shown on both charts and the three color-graded iPhone images. Medium versions are used where available; Bodycam Edge Stress and Internal Field Edge FX use their single included versions.</p></article>{''.join(preset_cards)}'''

diagnostic_html='''<article id="diagnostic-views"><p class="eyebrow">PROCESSING</p><h2>Diagnostic Views</h2><p class="lead">Diagnostic View temporarily replaces the normal image with information that helps identify and adjust individual parts of the effect.</p><table><thead><tr><th>View</th><th>What it shows</th></tr></thead><tbody>
<tr><th>Off</th><td>The normal Lens Debaser result.</td></tr>
<tr><th>Difference (Amplified)</th><td>The amplified difference between the processed result and the source, centered on middle grey. Neutral grey means no change; brighter, darker or colored areas show where the plugin changes the image.</td></tr>
<tr><th>Scatter Only</th><td>Only the combined Bloom, Glare, Spherical Halo and Anamorphic Flare contribution, amplified for inspection. A black image means those controls are producing no scatter energy on the current frame.</td></tr>
<tr><th>Direct Optics Only</th><td>The direct optical result—including geometry, field, detail, chromatic, transmission and aperture processing—without Bloom, Glare, Spherical Halo or Anamorphic Flare added.</td></tr>
<tr><th>Depth Input</th><td>The normalized depth map Lens Debaser is using after Depth Interpretation and the Input Near/Input Far remap. Black represents 0 and white represents 1.</td></tr>
<tr><th>Defocus Amount</th><td>A grayscale view of distance from Focus Depth after the current depth response. Dark areas are closer to the focus plane; bright areas receive more defocus.</td></tr>
<tr><th>Depth Rejection</th><td>A grayscale view of depth boundaries protected from cross-layer scatter. Brighter areas show stronger sample rejection caused by Depth Edge Protection.</td></tr>
</tbody></table><p class="fine">Diagnostic View changes only the displayed output. It does not alter the current preset or the stored lens controls.</p></article>'''

roots=[]
for _,root,_,_ in groups:
    if root not in roots: roots.append(root)
nav=''.join(f'<a href="#root-{root.lower().replace(" & ", "-").replace(" ", "-")}">{root}</a>' for root in roots)
sections=[]
active_root=None
depth_workflow='''<div class="control-workflow"><h3>Using a depth map on the Color page</h3><ol><li>Create or supply a grayscale depth map and connect its RGB output to Lens Debaser’s <b>Second RGB/Depth Map</b> input.</li><li>Choose one of the six <b>Depth Interpretation models</b> to match how the map stores distance:<ul><li><b>Depth-Free</b> does not use the external depth input. Lens Debaser retains its image- and field-based focus approximation.</li><li><b>Near White</b> is for normalized maps in which lighter values are closer and darker values are farther away.</li><li><b>Near Black</b> is for normalized maps in which darker values are closer and lighter values are farther away.</li><li><b>Linear Camera Z</b> is for camera-space distance that increases linearly from the near range toward the far range.</li><li><b>Inverse Z / Disparity</b> is for reciprocal-depth or disparity maps, where nearby subjects have larger values. Lens Debaser reverses this relationship into its common near-to-far working direction.</li><li><b>Logarithmic Z</b> is for depth distributed logarithmically, providing finer separation through the near range while compressing more distant values.</li></ul></li><li>Use <b>Input Near</b> and <b>Input Far</b> to fit the useful range of the incoming map. This is especially helpful when the map occupies only a narrow part of the available black-to-white range.</li><li>Select <b>Diagnostic View → Depth Input</b> to verify the interpreted and remapped depth signal, then return Diagnostic View to <b>Off</b> for normal processing.</li><li>Move <b>Focus Depth</b> to place the in-focus plane. <b>Defocus Onset</b> controls how far depth must move away from that plane before the enabled effect begins; <b>Defocus Falloff</b> controls how gradually it reaches full strength.</li><li>Increase <b>Depth Edge Protection</b> when foreground and background colors contaminate one another across depth boundaries. Use <b>Depth Edge Softness</b> to keep that protection from producing an unnaturally hard transition.</li><li>Enable at least one compatible optical response. If none is active, changing the depth controls may produce no visible result.</li></ol><h4>Depth-aware responses in this build</h4><ul><li><b>Aperture Response and bokeh reconstruction:</b> depth controls the defocus radius around Focus Depth. The active aperture shape, Cat-Eye, Bokeh Swirl, Pupil Shift, Pupil Clipping and Pupil Rim Weight are carried into that depth-positioned bokeh.</li><li><b>Longitudinal chromatic aberration:</b> depth chooses the near- or far-focus color and controls how strongly that focus color appears away from the focus plane.</li><li><b>Spherical Halo:</b> halo strength follows distance from Focus Depth and respects protected depth boundaries.</li><li><b>Anamorphic flare, diffraction and reflection structure:</b> depth affects source eligibility and prevents the reconstructed flare response from freely crossing unrelated depth layers.</li><li><b>Bloom and Glare:</b> these remain driven by qualifying highlights, while the depth map protects foreground/background boundaries from inappropriate cross-layer spill.</li><li><b>Front Element Wear scatter and Internal Element Contamination scatter:</b> their diffused-light components share the protected optical-scatter path. The fixed wear or contamination pattern itself is not repositioned by depth.</li></ul><p><b>Not depth-aware:</b> geometry, lateral chromatic aberration, vignette, transmission, detail transfer, field shape, refractive irregularity and prism refraction remain image- or field-based. Depth Input also provides the Depth Input, Defocus Amount and Depth Rejection diagnostic views for checking the map and its influence.</p></div>'''
for slug,root,title,_ in groups:
    if root != active_root:
        root_slug=root.lower().replace(" & ", "-").replace(" ", "-")
        sections.append(f'<article class="root-intro" id="root-{root_slug}"><p class="eyebrow">ROOT CONTROL GROUP</p><h2>{root}</h2><p class="lead">{root_descriptions[root]}</p></article>')
        active_root=root
    lead,body=descriptions[slug]
    workflow=depth_workflow if slug == "depth" else ""
    sections.append(f'<section id="{slug}"><div><p class="eyebrow">{root} / CONTROL GROUP</p><h2>{title}</h2><p class="lead">{lead}</p><p>{body}</p>{workflow}<p class="section-jump"><a href="#example-{slug}">See it in action ↓</a></p></div><img src="{image_uri(slug)}" alt="Illustrated Lens Debaser {root} and {title} control layout" loading="lazy" decoding="async"></section>')
    if slug == "processing":
        sections.append(diagnostic_html)

def medium_preset_for_family(family_number):
    matches=sorted((ROOT / "presets" / "cinematic-lenses").glob(f"{family_number:02d}-*-2-Medium.ldbpreset"))
    if matches:
        return matches[0]
    matches=sorted((ROOT / "presets" / "cinematic-lenses").glob(f"{family_number:02d}-*.ldbpreset"))
    return matches[0] if matches else None

preset_rows=''.join(
    f'<tr><th><a href="#preset-example-{guide_file_slug(medium_preset_for_family(index).stem)}">{name}</a></th><td>{description}</td></tr>'
    if medium_preset_for_family(index) else f'<tr><th>{name}</th><td>{description}</td></tr>'
    for index,(name,description) in enumerate(lens,start=1)
)
demonstration_count=len(list((ROOT / "presets" / "demonstrations").glob("*.ldbpreset")))
cinematic_count=len([p for p in (ROOT / "presets" / "cinematic-lenses").glob("*.ldbpreset")
                     if not p.name.endswith(" 2.ldbpreset")])
factory_preset_count=demonstration_count+cinematic_count
GUIDE_URL="https://vidarandersen.com/dmz/lens-debaser-ofx/"
REPOSITORY_URL="https://github.com/blacktar/lens-debaser"
RELEASES_URL=f"{REPOSITORY_URL}/releases"
guide_description=(
    "User guide for Lens Debaser, an experimental Apple Silicon Metal/OpenFX "
    "lens-character effect for DaVinci Resolve."
)
structured_data={
 "@context":"https://schema.org",
 "@graph":[
  {
   "@type":"SoftwareApplication",
   "@id":f"{GUIDE_URL}#software",
   "name":"Lens Debaser",
   "alternateName":"Lens Debaser OFX",
   "description":"An experimental Apple Silicon Metal/OpenFX effect that adds controllable optical character to footage in DaVinci Resolve.",
   "applicationCategory":"MultimediaApplication",
   "applicationSubCategory":"Video post-production plug-in",
   "operatingSystem":"macOS on Apple Silicon",
   "softwareVersion":VERSION,
   "datePublished":RELEASE_DATE_ISO,
   "softwareRequirements":"Apple Silicon Mac, Metal, and DaVinci Resolve or DaVinci Resolve Studio",
   "processorRequirements":"Apple Silicon (arm64)",
   "isAccessibleForFree":True,
   "license":"https://creativecommons.org/licenses/by-nc-sa/4.0/",
   "url":REPOSITORY_URL,
   "downloadUrl":RELEASES_URL,
   "sameAs":[REPOSITORY_URL],
   "author":{"@type":"Person","name":"Vidar Andersen"},
   "dateModified":RELEASE_DATE_ISO,
   "image":f"{GUIDE_URL}images/logo.webp"
  },
  {
   "@type":"TechArticle",
   "@id":f"{GUIDE_URL}#guide",
   "headline":f"Lens Debaser {VERSION} User Guide",
   "name":f"Lens Debaser {VERSION} User Guide",
   "description":guide_description,
   "url":GUIDE_URL,
   "mainEntityOfPage":{"@type":"WebPage","@id":GUIDE_URL},
   "about":{"@id":f"{GUIDE_URL}#software"},
   "author":{"@type":"Person","name":"Vidar Andersen"},
   "inLanguage":"en",
   "license":"https://creativecommons.org/licenses/by-nc-sa/4.0/",
   "isAccessibleForFree":True,
   "image":f"{GUIDE_URL}images/logo.webp"
  }
 ]
}
structured_data_json=json.dumps(structured_data,ensure_ascii=False,separators=(",",":"))
demo_descriptions=(
 ("Capture","Supplies peripheral detail loss, field curvature, longitudinal focus color and natural vignetting, then enables Capture Influence. Those four effects form the visible base image; the Capture settings coordinate their strength according to the simulated focal length, aperture, focus distance and capture gate."),
 ("Look","Coordinates several existing optical responses so each broad Look bias is visibly educational rather than neutral on its own."),
 ("Field-Gated Geometry","Uses conventional distortion plus the Field envelope; straight architectural lines and grids reveal the protected center and gradual edge onset."),
 ("Field Shape","Activates an elliptical, rotated and offset optical field plus its Onset/Falloff envelope; compatible focus and chromatic effects make every field control visible."),
 ("Focus & Field","Combines corner detail loss, field curvature, astigmatism and directional smears while retaining a clearer region around the Field Center."),
 ("Detail Transfer","Demonstrates broad microcontrast, fine-detail transfer, edge falloff and sagittal/tangential differences; textured fabric, foliage and fine line charts are suitable inputs."),
 ("Chromatic Aberration","Combines lateral and longitudinal chromatic response; use high-contrast edges and fine bright detail for the clearest color separation."),
 ("Anamorphic","Combines anamorphic distortion, aberration and streak flare. Geometry is visible on lines; flare requires highlights above Flare Threshold."),
 ("Aperture & Bokeh","Uses modest aperture reconstruction, a shaped pupil, Cat-Eye and Bokeh Swirl plus an off-axis focus field. Small bright points reveal the pupil while the field envelope preserves a usable centre."),
 ("Vignette","Combines natural, optical and mechanical edge attenuation; a flat or evenly exposed image makes their different falloffs easiest to compare."),
 ("Image Circle","Enables Mechanical Vignette because Image Circle Size, Aspect and Softness have no visible effect without it."),
 ("Bloom","Lowers Bloom Threshold and spreads qualifying highlights. Use lamps, reflections, bright windows or overexposed edges."),
 ("Glare & Halo","Enables glare and spherical halo with highlight-friendly settings. It requires strong highlights, ideally isolated against darker surroundings."),
 ("Transmission","Demonstrates glass color, density, contrast and highlight compression across the whole tonal range; include neutral greys, skin and bright values."),
 ("Highlight Response","Enables several highlight effects so Highlight Knee visibly reshapes their threshold transitions. Use bright practicals, reflections or windows."),
 ("Coma","Uses isolated bright points away from Field Center to expose asymmetric off-axis tails and their threshold."),
 ("Variation","Enables field, pupil, chromatic and transmission base effects before varying them, so the deterministic Seed has compatible responses to modify."),
 ("Depth Input","Requires a depth map connected to the Second RGB/Depth Map input. It enables neutral depth-aware aperture and halo responses and assumes Near Black interpretation."),
 ("Blend","Mixes a moderate compound optical treatment to demonstrate the final result at 100% effect and 50% Blend."),
 ("Front Element Wear","Uses strong highlights and ordinary detail to expose cleaning haze, fixed marks, scratches and patchy coating wear."),
 ("Refractive Irregularity","Uses a grid and fine contrast to reveal stable local magnification waves and irregular dispersion without conventional distortion."),
 ("Peripheral Stretch","Isolates smooth radial magnification that increases gradually toward the edge while preserving the center."),
 ("Peripheral Warp","Isolates nonuniform optical edge bending under the shared Field envelope."),
 ("Internal Element Contamination","Uses broad seeded contamination clouds to demonstrate localized contrast loss and illumination-driven veiling; bright windows and practicals reveal Scatter most clearly."),
 ("Bokeh Swirl","Uses off-axis point highlights and a shaped field to isolate continuous tangential pupil deformation without replacing the underlying pupil."),
 ("Petzval Field","Combines field curvature, swirl, oval pupil response and a protected portrait centre; use a subject against distributed background lights."),
 ("Structured Anamorphic Flare","Uses one compact bright source on a dark frame to expose the continuous core, bands, secondary streak and decaying internal-reflection train."),
 ("Diffraction Rays","Uses compact clipped highlights on a dark scene to reveal smooth full-resolution vertical diffraction without segmented steps."),
 ("Pupil Decenter & Clipping","Uses off-axis point highlights to show radial pupil shift and asymmetric barrel clipping independently of generic blur."),
 ("Bubble Rim Bokeh","Uses sparse defocused points to show the transition between a filled pupil and a brighter rim without retaining a sharp source core."),
)
demo_reference_slugs={
 "Capture":"capture",
 "Look":"look",
 "Field-Gated Geometry":"geometry",
 "Field Shape":"field-shape",
 "Focus & Field":"focus-field",
 "Detail Transfer":"detail",
 "Chromatic Aberration":"chromatic",
 "Anamorphic":"anamorphic",
 "Aperture & Bokeh":"aperture",
 "Vignette":"vignette",
 "Image Circle":"image-circle",
 "Bloom":"bloom",
 "Glare & Halo":"glare-halo",
 "Transmission":"transmission",
 "Highlight Response":"highlight-response",
 "Coma":"off-axis",
 "Variation":"variation",
 "Depth Input":"depth",
 "Blend":"blend",
 "Front Element Wear":"front-wear",
 "Refractive Irregularity":"refractive",
 "Peripheral Stretch":"geometry",
 "Peripheral Warp":"geometry",
 "Internal Element Contamination":"internal-contamination",
 "Bokeh Swirl":"aperture",
 "Petzval Field":"focus-field",
 "Structured Anamorphic Flare":"anamorphic",
 "Diffraction Rays":"anamorphic",
 "Pupil Decenter & Clipping":"aperture",
 "Bubble Rim Bokeh":"aperture",
}
demo_rows=''.join(
    f'<li><b><a href="#example-{demo_reference_slugs[title]}">{title}</a></b> — {description}</li>'
    for title,description in demo_descriptions
)
guide_css="""
:root{--ink:#e5e8ea;--muted:#9aa2a8;--paper:#111315;--card:#1b1e21;--line:#303438;--acid:#d9ff42;--orange:#ff9738}*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;color:var(--ink);background:var(--paper);font:17px/1.65 Inter,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif}a{color:#16cbf6}header.hero{padding:8vw max(6vw,30px) 7vw;background:#090b0c;color:white;position:relative;overflow:hidden}.hero:after{content:'Ldb';position:absolute;right:-.02em;bottom:-.45em;font-size:32vw;font-weight:900;color:#171a1c;z-index:0}.hero>*{position:relative;z-index:1}.kicker,.eyebrow{text-transform:uppercase;letter-spacing:.18em;font-size:.72rem;font-weight:800;color:var(--orange)}h1{font-size:clamp(3.4rem,9vw,9rem);line-height:.84;max-width:1000px;margin:.22em 0}.hero .intro{max-width:700px;font-size:1.3rem;color:#c9d0d4}.badge{display:block;color:var(--acid);font-weight:800;margin-top:1.5em}.hero-cta{display:inline-block;margin-top:1.1em;padding:.75em 1.05em;border:1px solid var(--orange);color:var(--orange);font-weight:800;text-decoration:none}.hero-cta[aria-disabled="true"]{cursor:default}.menu-bar{position:sticky;top:0;z-index:10;background:#171a1c;border-bottom:1px solid var(--line);padding:10px 5vw}.menu-button{display:flex;align-items:center;gap:11px;background:transparent;color:#eef1f2;border:1px solid #454b50;padding:9px 13px;font:inherit;font-size:.85rem;cursor:pointer}.menu-icon,.menu-icon:before,.menu-icon:after{display:block;width:19px;height:2px;background:currentColor;content:'';transition:.2s}.menu-icon{position:relative}.menu-icon:before{position:absolute;top:-6px}.menu-icon:after{position:absolute;top:6px}.menu-button[aria-expanded="true"] .menu-icon{background:transparent}.menu-button[aria-expanded="true"] .menu-icon:before{top:0;transform:rotate(45deg)}.menu-button[aria-expanded="true"] .menu-icon:after{top:0;transform:rotate(-45deg)}nav{display:none;position:absolute;left:5vw;right:5vw;top:100%;max-height:70vh;overflow:auto;background:#171a1c;border:1px solid var(--line);padding:14px;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:4px}nav.open{display:grid}nav a{color:#16cbf6;text-decoration:none;font-size:.82rem;padding:8px 10px}nav a:hover,nav a:focus{background:#262a2d;color:white}.wrap{max-width:1300px;margin:auto;padding:70px 5vw}.notice{background:#202428;color:white;padding:28px 34px;border-left:8px solid var(--acid);margin-bottom:50px}.notice b{color:var(--acid)}h2{font-size:clamp(2rem,4vw,4rem);line-height:1;margin:.12em 0 .35em}.lead{font-size:1.25rem;font-weight:650}.root-intro{margin:100px 0 0;padding:42px;border:1px solid var(--line);border-left:8px solid var(--orange);background:var(--card)}section{display:grid;grid-template-columns:minmax(280px,.85fr) minmax(420px,1.15fr);gap:55px;align-items:center;padding:70px 0;border-bottom:1px solid var(--line)}section img{width:100%;border:1px solid #3c4145;border-radius:2px;box-shadow:none;background:#25282c}article{margin:80px 0}.steps{counter-reset:x;display:grid;grid-template-columns:repeat(4,1fr);gap:16px}.steps div{background:var(--card);border:1px solid var(--line);padding:24px;min-height:180px}.steps div:before{counter-increment:x;content:counter(x);display:block;font-weight:900;font-size:2rem;color:var(--orange)}table{width:100%;border-collapse:collapse;background:var(--card);border:1px solid var(--line)}th,td{text-align:left;vertical-align:top;padding:15px;border-bottom:1px solid var(--line)}th{width:30%}.demo-list{columns:2;column-gap:40px}.demo-list li{break-inside:avoid;margin:0 0 14px}.fine{color:var(--muted);font-size:.9rem}footer{background:#090b0c;color:#bbc2c6;padding:60px 6vw;border-top:1px solid var(--line)}@media(max-width:800px){section{grid-template-columns:1fr;gap:25px}.steps{grid-template-columns:1fr}.demo-list{columns:1}.wrap{padding-top:35px}nav{grid-template-columns:1fr 1fr;left:0;right:0}.hero .intro{font-size:1.1rem}}@media(max-width:480px){nav{grid-template-columns:1fr}h1{font-size:3.2rem}.notice{padding:22px}.root-intro{padding:26px}section{padding:45px 0}}@media print{.menu-bar{display:none}section{break-inside:avoid}.hero{padding:50px}.hero:after{display:none}}
"""
guide_css += ":root{--orange:#16cbf6;--acid:#16cbf6}"
guide_css += ".menu-bar{margin-top:-12px}"
guide_css += """
.hero{display:grid;grid-template-columns:minmax(0,1fr) minmax(180px,340px);gap:clamp(35px,7vw,110px);align-items:center}
.hero-copy{min-width:0}.hero h1 span{display:block;font-weight:900}.hero-logo{display:block;width:100%;height:auto;justify-self:end}
.hero-cta{border:0;background:var(--acid);color:#000;transition:background-color .18s ease}.hero-cta:hover,.hero-cta:focus-visible{background:#16cbf680}
.disclaimer{padding:34px 38px;border:1px solid #16cbf68a;border-left:8px solid var(--acid);background:#052b34}.disclaimer h2{font-size:clamp(2rem,4vw,3.2rem)}.disclaimer p:last-child{margin-bottom:0}
.guide-version{display:grid;grid-template-columns:auto auto;justify-content:space-between;gap:.5em 2em;margin:0 0 22px;padding:14px 18px;border:1px solid var(--line);background:var(--card);font-size:.9rem}.guide-version p{margin:0}.guide-version b{color:var(--acid)}.guide-version .release-summary{grid-column:1/-1;color:var(--muted)}
@media(max-width:800px){.hero{grid-template-columns:minmax(0,1fr) minmax(110px,25vw);gap:25px}}
@media(max-width:560px){.hero{grid-template-columns:1fr}.hero-logo{width:min(55vw,220px);justify-self:start;grid-row:1}.hero-copy{grid-row:2}}
.examples-intro{margin-bottom:20px}.example-card{display:block;padding:55px 0}.example-card h3{font-size:2rem;margin:.15em 0 .35em}.example-card>div:first-child{max-width:850px}.applied-recipe{margin-top:1.2em;padding:.7em .9em;border-left:3px solid var(--orange);background:var(--card)}.applied-recipe code{color:var(--acid)}.example-gallery{display:grid;grid-template-columns:1fr;gap:24px;margin-top:26px}.image-compare{position:relative;overflow:hidden;width:100%;aspect-ratio:var(--media-aspect,16/9);margin:0;background:#090b0c;border:1px solid #3c4145;user-select:none}.image-compare>img,.before-layer,.before-layer img{position:absolute;inset:0;width:100%;height:100%;object-fit:contain}.before-layer{width:var(--split);overflow:hidden}.before-layer img{max-width:none}.compare-divider{position:absolute;top:0;bottom:0;left:var(--split);width:2px;background:white;box-shadow:0 0 0 1px #0008;transform:translateX(-1px);pointer-events:none}.compare-divider:after{content:'↔';position:absolute;top:50%;left:50%;display:grid;place-items:center;width:38px;height:38px;border-radius:50%;background:white;color:#111;font-weight:900;transform:translate(-50%,-50%)}.image-compare input{position:absolute;inset:0;width:100%;height:100%;margin:0;opacity:0;cursor:ew-resize}.compare-label{position:absolute;top:12px;padding:5px 8px;background:#090b0ccc;color:white;font-size:.72rem;font-weight:800;text-transform:uppercase;letter-spacing:.1em;pointer-events:none}.before-label{left:12px}.after-label{right:12px}
.section-jump{margin:1.15em 0 0}.section-jump a{display:inline-block;font-size:.8rem;font-weight:800;letter-spacing:.08em;text-decoration:none;text-transform:uppercase}.section-jump a:hover,.section-jump a:focus-visible{text-decoration:underline;text-underline-offset:.2em}
#ai-presets h3{margin-top:2em}#ai-presets pre{overflow-x:auto;padding:20px;border:1px solid var(--line);background:#090b0c;color:#e9eef0;white-space:pre-wrap}#ai-presets pre code{color:inherit}
@media(max-width:800px){.image-compare{min-width:0}}
"""
html=f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Lens Debaser {VERSION} — User Guide</title><meta name="description" content="{guide_description}"><meta name="robots" content="index,follow,max-image-preview:large"><link rel="canonical" href="{GUIDE_URL}"><meta property="og:type" content="article"><meta property="og:title" content="Lens Debaser {VERSION} — User Guide"><meta property="og:description" content="{guide_description}"><meta property="og:url" content="{GUIDE_URL}"><meta property="og:image" content="{GUIDE_URL}images/logo.webp"><meta property="og:site_name" content="Lens Debaser"><meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="Lens Debaser {VERSION} — User Guide"><meta name="twitter:description" content="{guide_description}"><meta name="twitter:image" content="{GUIDE_URL}images/logo.webp"><script type="application/ld+json">{structured_data_json}</script><style>{guide_css}</style></head><body>
<header class="hero"><div class="hero-copy"><p class="kicker">Lens Debaser {VERSION} · User guide</p><h1><span>Lens</span><span>Debaser</span><span>OFX</span></h1><p class="intro">Lens Debaser is an Apple-Silicon Metal/OpenFX effect for DaVinci Resolve. It can add spatial, chromatic, tonal, and highlight character to your too-perfect footage.</p><p class="intro">Because all cameras are good now. Too good. So I made this for you to debase perfectly good optics in post - because perfect modern optics is for OnlyFans - not for <strong>ABSOLUTE CINEMA!</strong></p><span class="badge">DEBASE PERFECTLY GOOD OPTICS IN POST</span><a class="hero-cta" href="https://github.com/blacktar/lens-debaser/releases">Get Lens Debaser now</a></div><img class="hero-logo" src="{image_uri('logo')}" alt="Lens Debaser logo" loading="eager" decoding="async" fetchpriority="high"></header><div class="menu-bar"><button class="menu-button" type="button" aria-expanded="false" aria-controls="guide-menu"><span class="menu-icon" aria-hidden="true"></span><span>Guide menu</span></button><nav id="guide-menu"><a href="#disclaimer">Work in Progress</a><a href="#installation">Installation</a>{nav}<a href="#diagnostic-views">Diagnostic Views</a><a href="#control-examples">Control examples</a><a href="#preset-examples">Preset examples</a><a href="#catalogue">Preset catalogue</a><a href="#ai-presets">Create presets with AI</a><a href="#credits">Acknowledgements &amp; Credits</a></nav></div><main class="wrap">
<article class="guide-version" aria-label="Guide version"><p><b>Current build:</b> Lens Debaser {VERSION}</p><p><b>Release date:</b> <time datetime="{RELEASE_DATE_ISO}">{RELEASE_DATE}</time></p><p class="release-summary">{RELEASE_SUMMARY}</p></article>
<article id="disclaimer" class="disclaimer"><p class="eyebrow">WORK IN PROGRESS</p><h2>Experimental software</h2><p>Lens Debaser is under active development. Features, controls, presets, results, compatibility and performance may change without notice. Parts of the plugin may break, behave unexpectedly, or not work entirely as described in this guide.</p><p>Lens Debaser is not a scientific ray tracer. It uses perceptually useful approximations of lens effects rather than attempting mathematically exact optical simulation. The aim is to produce convincing, controllable results while keeping render times practical for post-production and color-grading workflows.</p><p>The software and this guide are provided <b>as is</b> and <b>as available</b>, without warranties of any kind, express or implied. To the fullest extent permitted by applicable law, the authors and contributors accept no liability for loss, damage, interrupted work, corrupted projects, lost media or any other consequence arising from installation or use. Test the plugin on copies of important projects and media.</p></article>
<article id="installation"><p class="eyebrow">INSTALLATION</p><h2>Install the compiled plug-in</h2><p class="lead">The release package contains the ready-built Apple Silicon OpenFX plug-in, its Metal processing library, factory presets and an installer. Xcode and developer tools are not required.</p><div class="steps"><div><b>Unpack the release</b><br>Double-click the downloaded Lens Debaser ZIP file to extract its folder.</div><div><b>Quit Resolve</b><br>Fully quit DaVinci Resolve before installing or replacing the plug-in.</div><div><b>Run the installer</b><br>Double-click <b>Install Lens Debaser.command</b> and enter the Mac administrator password when requested. If macOS blocks it, Control-click the installer, choose Open, then confirm.</div><div><b>Restart Resolve</b><br>Open Resolve and find Lens Debaser in the OpenFX effects library. The installer also copies the included factory presets into the Lens Debaser preset folder.</div></div><p class="fine"><b>Requirements:</b> an Apple Silicon Mac and DaVinci Resolve or DaVinci Resolve Studio. Installing a newer release automatically saves the previous plug-in bundle in <code>/Library/Application Support/Lens Debaser/Backups</code>.</p></article>
<article><p class="eyebrow">QUICK START</p><h2>Four steps to results</h2><div class="steps"><div><b>Add Lens Debaser</b><br>Add Lens Debaser to a clip node on the Color page for an individual shot. If every clip was captured with the same camera and lens—such as a timeline of smartphone footage—add it to a timeline node to apply one consistent optical treatment across the entire edit.</div><div><b>Match the input</b><br>Choose the Input Working Space that matches the image entering the node.</div><div><b>Choose a starting point</b><br>Load a preset or begin with Clean Slate, then adjust the controls for the shot.</div><div><b>Optional: set the final strength</b><br>Use Blend when you want to mix the complete Lens Debaser result with the original image.</div></div></article>
{''.join(sections)}
<article><p class="eyebrow">DEMONSTRATIONS</p><h2>Explore individual control groups</h2><p>The Demonstrations folder contains one moderate educational preset per major control group or required interaction. Each is tuned as a usable starting point while remaining clear enough to explain the control; its note identifies the input features or dependencies needed to reveal the response.</p><ul class="demo-list">{demo_rows}</ul></article>
{examples_html}
<article id="catalogue"><p class="eyebrow">CINEMATIC LENSES</p><h2>Default character presets</h2><p class="lead">The current library contains {factory_preset_count} factory presets: {demonstration_count} demonstrations and {cinematic_count} cinematic-lens presets.</p><p>Most cinematic families provide independently authored Subtle, Medium and Caricature observations. Subtle introduces the family with a restrained change, Medium is a clearly visible starting point, and Caricature exposes the defining signature strongly. Bodycam Edge Stress and Internal Field Edge FX are single signature presets. Presets containing aperture reconstruction use controlled values and combine them with a clearer focus region; a connected depth map gives direct control over the in-focus plane.</p><table><thead><tr><th>Family</th><th>Character and suitable input</th></tr></thead><tbody>{preset_rows}</tbody></table></article>
{preset_examples_html}
<article id="ai-presets"><p class="eyebrow">NEW IN THIS RELEASE · VIBE-CODE YOUR LOOKS</p><h2>Create optical responses entirely inside an AI client</h2><p class="lead">You do not need to know programming, optical mathematics or how to use a command line. Describe the image character you want in everyday language and an AI assistant such as ChatGPT can create, check and attach a finished Lens Debaser preset for you to download. The Preset Authoring Kit supplies the assistant with the real controls, allowed ranges and rules for the current plug-in.</p><p><b>The entire authoring workflow takes place in the AI client:</b> it creates the preset file, checks it and provides the download. Lens Debaser does not connect to an AI service; it simply loads the finished <code>.ldbpreset</code> in Resolve.</p>
<h3>1. Get the authoring files for your Lens Debaser version</h3><p><b>Always use the Preset Authoring Kit that matches the Lens Debaser version for which you are creating the preset.</b> Controls, ranges, choices and dependencies may change between releases. The newest kit is not guaranteed to work with an older installed plug-in, and an older kit may omit or misdescribe controls in a newer one. The kit included inside each release archive is the authoritative package for that version.</p><p>Open the matching <b>Preset Authoring Kit</b> and provide <code>Lens-Debaser-Preset-Schema.json</code> and <code>Clean-Slate-Template.ldbpreset</code> to the AI assistant. The schema explains every available setting; the template shows the required file format. The <b>examples</b> folder contains finished recipes you may also provide as references.</p><p><a href="https://github.com/blacktar/lens-debaser/tree/main/preset-authoring">Get the Preset Authoring Kit →</a></p>
<h3>2. Start a new AI conversation</h3><p>Open ChatGPT or another assistant that accepts file attachments. Begin a new conversation so unrelated instructions do not influence the result. Attach the schema and clean template. If you want something structurally similar to one of the included examples, attach that example too.</p>
<h3>3. Describe the result you want</h3><p>Explain the desired appearance as you would to a colorist. Useful details include whether the centre should remain sharp, what should happen near the edges, how highlights and out-of-focus points should behave, whether color fringing is wanted, and whether the effect should be subtle, clearly visible or extreme. Mention the kind of footage you intend to use. A description such as “soft vintage portrait glass with a protected centre, gentle edge curvature, warm highlight diffusion and oval background bokeh” is more useful than simply asking for “a cinematic lens.”</p>
<h3>4. Give the assistant a clear instruction</h3><p>Copy this starter request after your visual description:</p><pre><code>Using the attached Lens Debaser schema and template, create one valid
LensDebaserPreset=2 file for this optical response. Use only controls listed
in the schema, obey their ranges and dependencies, and activate the fewest
control groups needed. Prefer a convincing, responsive approximation over an
extreme effect. Do not include unchanged defaults, Input Working Space or
Diagnostic View. Explain what the preset does, recommend suitable test images,
validate the result against the schema, and create the finished preset as a
downloadable .ldbpreset file beginning with LensDebaserPreset=2. Do not ask me
to copy source text, use a text editor, rename a file or run a command.</code></pre>
<h3>5. Download the finished preset</h3><p>The AI client should create the actual file for you. Download the attached <code>.ldbpreset</code> directly from the conversation and place it in a folder where you want to keep your custom Lens Debaser looks. You should not need to copy a code block, use TextEdit, change a file extension or open Terminal. If the assistant responds with instructions instead of a downloadable file, ask it explicitly to create and attach the finished file.</p>
<h3>6. Let the AI check it, then load it</h3><p>Before downloading, ask the assistant to reopen its generated file and check the header, every control name, value range, choice, dependency and required second input against the attached schema. Then add Lens Debaser to a node in Resolve, click <b>Load</b> in the Presets group, and choose the downloaded <code>.ldbpreset</code>. Loading one file also makes the other valid presets in that folder available in the Preset menu.</p>
<h3>7. Test more than one image</h3><p>Judge the result on appropriate material: a face, fine detail, hard contrast edges, small bright highlights, defocused lights and moving footage. Use a depth map when the recipe requires one. Check the full frame for clipped or repeated edges, excessive color, obvious layered blur and distracting motion. A preset that looks interesting on a chart may still look artificial on a real shot.</p>
<h3>8. Ask for focused revisions</h3><p>Keep the schema and current preset attached in the same AI conversation. Describe one visible problem at a time—for example, “protect the face in the centre,” “make the oval bokeh stronger without increasing overall blur,” or “reduce edge color while keeping the prism bend.” Ask the assistant to change only the controls needed for that correction, validate the revision and attach it as a new downloadable <code>.ldbpreset</code>. Tell it to preserve each promising version under a distinct file name so you can compare results and return to an earlier look.</p>
<p class="fine"><b>Remember:</b> file validation confirms that a preset is structurally compatible; it cannot determine whether the result is attractive or appropriate. Treat AI-generated settings as creative starting points and approve them by looking at the rendered image.</p></article>
<article><p class="eyebrow">PRACTICAL NOTES</p><h2>Performance and troubleshooting</h2><ul><li><b>Platform compatibility:</b> Lens Debaser is an Apple Silicon and Metal-only OpenFX plug-in. It requires an Apple Silicon Mac and is not available for Intel Macs, Windows, Linux, CUDA or OpenCL.</li><li><b>Aperture &amp; Bokeh processing:</b> shaped aperture reconstruction is one of Lens Debaser’s more processing-intensive effects, especially with a large Response Radius, depth-driven defocus, or high-resolution footage. Enable it when shaped bokeh is wanted, begin with a modest radius, and leave Aperture Response at zero when it is not needed so the stage and its processing cost remain bypassed.</li><li><b>Bloom, glare and anamorphic flare:</b> each effect uses its own Threshold control. Lower the relevant threshold if an expected lamp, reflection or window produces no response. Changing Bloom Threshold does not change Glare. Rays and reflections remain smooth at full output resolution.</li><li><b>Response controls:</b> Field Shape determines where active edge effects develop, Highlight Response changes how enabled glow and flare effects build around bright values, and Depth Input controls how enabled effects respond to focus distance and depth boundaries.</li><li><b>Variation:</b> the same Seed produces the same variation pattern.</li><li><b>Difference diagnostic:</b> this view amplifies changes between the original and processed images so subtle effects are easier to see.</li><li><b>Overall strength:</b> use Blend to reduce or increase the complete effect.</li></ul></article>
<article id="credits"><p class="eyebrow">CREDITS & LICENSING</p><h2>Acknowledgements &amp; Credits</h2><p>Lens Debaser is distributed under <a href="https://creativecommons.org/licenses/by-nc-sa/4.0/">Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International</a>. The complete terms are in the repository <code>LICENSE</code> file.</p><h3>Images</h3><ul><li>The color-graded iPhone 17 Pro images captured in Milan with a 1.55× anamorphic adapter (ProRes RAW Open Gate) were created by Vidar Andersen. The included source images and their Lens Debaser demonstration renders are distributed under the same <a href="https://creativecommons.org/licenses/by-nc-sa/4.0/">CC BY-NC-SA 4.0</a> license as Lens Debaser.</li><li>The Lens Debaser synthetic optical chart is an original, reproducible project asset used for geometry, field and sharpness demonstrations.</li></ul><h3>Code and platform</h3><ul><li><a href="https://github.com/AcademySoftwareFoundation/openfx">OpenFX</a> headers and C++ Support library — copyright OpenFX and contributors; <a href="https://github.com/AcademySoftwareFoundation/openfx/blob/main/Support/LICENSE">BSD 3-Clause License</a>.</li><li><a href="https://developer.apple.com/metal/">Apple Metal</a>, macOS frameworks and the Xcode toolchain provide GPU execution and compilation.</li><li><a href="https://www.blackmagicdesign.com/products/davinciresolve">DaVinci Resolve</a> is the supported OpenFX host and supplies the development SDK used to build the plug-in.</li></ul><h3>Colour science and validation</h3><ul><li><a href="https://acescentral.com/">Academy Color Encoding System (ACES)</a> documentation informs ACEScg/AP1 and ACEScct handling.</li><li><a href="https://www.arri.com/en/learn-help/learn-help-camera-system/image-science/log-c">ARRI Log C</a> documentation informs LogC3/LogC4 handling.</li></ul><h3>Optical-model design references</h3><p>Lens Debaser uses an original real-time approximation and does not incorporate source code from these publications. Their image-formation concepts inform the implemented chromatic pipeline: a shared optical point-spread response, wavelength-dependent RGB responses, smooth spatially varying filtering, and chromatic displacement applied after optical softness.</p><ul><li>Jeong et al., <a href="https://cg.skku.edu/pub/papers/2016-jeong-cgi-chroma-cam.pdf">Chromatic Aberration Rendering for a Physically-based Camera</a>.</li><li>Mantiuk et al., <a href="https://pmc.ncbi.nlm.nih.gov/articles/PMC10023823/">Rendering Algorithms for Aberrated Human Vision Simulation</a>.</li><li>Bauer et al., <a href="https://arxiv.org/abs/2208.00950">Fast Two-step Blind Optical Aberration Correction</a>.</li><li>NVIDIA Research, <a href="https://research.nvidia.com/sites/default/files/pubs/2009-08_Image-Space-Gathering/HPG09-ISG.pdf">Image-Space Gathering</a>.</li></ul></article>
</main><footer><b>Lens Debaser {VERSION}</b><br>Apple Silicon · Metal · OpenFX · DaVinci Resolve<br><span class="fine">CC BY-NC-SA 4.0.</span></footer><script>const button=document.querySelector('.menu-button');const menu=document.querySelector('#guide-menu');button.addEventListener('click',()=>{{const open=button.getAttribute('aria-expanded')==='true';button.setAttribute('aria-expanded',String(!open));menu.classList.toggle('open',!open)}});menu.addEventListener('click',event=>{{if(event.target.closest('a')){{menu.classList.remove('open');button.setAttribute('aria-expanded','false')}}}});document.addEventListener('keydown',event=>{{if(event.key==='Escape'){{menu.classList.remove('open');button.setAttribute('aria-expanded','false')}}}});document.querySelectorAll('[data-compare]').forEach(compare=>{{const range=compare.querySelector('input');const before=compare.querySelector('.before-layer img');const update=()=>{{compare.style.setProperty('--split',Number(range.value)+'%');before.style.width=compare.clientWidth+'px'}};range.addEventListener('input',update);new ResizeObserver(update).observe(compare);update()}});</script></body></html>'''
(DOC/'Lens-Debaser-User-Guide.html').write_text(html)
print(f"Built guide source for {len(groups)} control groups in {DOC}")
