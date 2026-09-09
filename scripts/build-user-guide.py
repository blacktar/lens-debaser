#!/usr/bin/env python3
"""Build the Lens Debaser HTML guide and its Resolve-style UI image source."""

from pathlib import Path
import base64

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / "docs" / "user-guide"
IMG = DOC / "images"
DOC.mkdir(parents=True, exist_ok=True)
IMG.mkdir(parents=True, exist_ok=True)

groups = [
 ("presets","Setup","Presets",[("Preset","Warm Dimensional Prime — Medium","select"),("Load","Load","button"),("Save","Save","button")]),
 ("processing","Setup","Processing",[("Input Working Space","DaVinci Wide Gamut / Intermediate","select"),("Diagnostic View","Off","select")]),
 ("capture","Setup","Capture",[("Capture Influence","0.650","slider"),("Focal Length (mm)","35.0","slider"),("Aperture","2.00","slider"),("Gate / Capture Format","Super 35 24.89 × 18.66","select"),("Focus Distance (cm)","180","slider")]),
 ("look","Setup","Look",[("Character","0.350","slider"),("Vintage Bias","0.650","slider"),("Vintage Caricature","0.000","slider"),("Exotic Bias","0.000","slider"),("Classic 2x Anamorphic Bias","0.000","slider"),("Look Influence","1.000","slider")]),
 ("geometry","Optics","Geometry",[("Optical Center","X 0.500   Y 0.500","point"),("Primary Distortion","0.030","slider"),("Secondary Distortion","0.080","slider"),("Moustache","0.120","slider")]),
 ("field-shape","Optics","Field Shape",[("Field Center","X 0.500   Y 0.500","point"),("Swirl","0.300","slider"),("Field Aspect","1.150","slider"),("Field Rotation","8.0°","slider")]),
 ("focus-field","Optics","Focus & Field",[("Corner Detail Loss","0.650","slider"),("Astigmatism","0.250","slider"),("Field Curvature","0.450","slider"),("Radial Smear","0.180","slider"),("Tangential Smear","0.280","slider")]),
 ("detail","Optics","Detail Transfer",[("Microcontrast","−0.250","slider"),("Fine Detail","−0.150","slider"),("Edge Falloff","0.550","slider"),("Sagittal Detail","0.200","slider"),("Tangential Detail","−0.180","slider"),("Detail Scale","2.000","slider")]),
 ("chromatic","Optics","Chromatic Aberration",[("Red Fringing","0.650","slider"),("Blue Fringing","−0.850","slider"),("Longitudinal Amount","0.300","slider"),("Longitudinal Radius","4.00","slider"),("Near-Focus Color","","color"),("Far-Focus Color","","color")]),
 ("anamorphic","Optics","Anamorphic",[("Anamorphic Field","1.300","slider"),("Distortion","0.025","slider"),("Aberration","0.550","slider"),("Flare Amount","0.650","slider"),("Flare Radius","145","slider"),("Flare Threshold","0.800","slider"),("Flare Color","","color")]),
 ("aperture","Pupil & Vignette","Aperture",[("Aperture Shape","Oval / Anamorphic","select"),("Aperture Response","0.650","slider"),("Response Radius","15.00","slider"),("Blade Count","6","slider-disabled"),("Blade Curvature","0.500","slider-disabled"),("Aperture Rotation","0.0","slider"),("Edge Softness","0.500","slider"),("Cat-Eye","0.500","slider"),("Pupil Aspect","2.000","slider")]),
 ("vignette","Pupil & Vignette","Vignette",[("Natural Vignette","0.000","slider"),("Optical Vignette","0.180","slider"),("Mechanical Vignette","0.000","slider")]),
 ("image-circle","Pupil & Vignette","Image Circle",[("Image Circle Size","1.200","slider"),("Image Circle Aspect","1.000","slider"),("Image Circle Softness","0.100","slider")]),
 ("bloom","Light","Bloom",[("Bloom Amount","0.450","slider"),("Bloom Threshold","0.700","slider"),("Bloom Radius","52.0","slider"),("Bloom Stretch","1.800","slider")]),
 ("glare-halo","Light","Glare & Halo",[("Spherical Halo","0.350","slider"),("Glare Amount","0.320","slider"),("Glare Radius","58.0","slider"),("Glare Color Amount","0.180","slider"),("Glare Color","","color")]),
 ("transmission","Light","Transmission",[("Transmission Amount","0.280","slider"),("Transmission Density","0.180","slider"),("Transmission Contrast","−0.220","slider"),("Highlight Softness","0.550","slider"),("Transmission Color","","color")]),
 ("off-axis","Advanced","Off-Axis Character",[("Coma","0.280","slider"),("Coma Threshold","0.500","slider")]),
 ("variation","Advanced","Variation",[("Variation Amount","0.650","slider"),("Variation Seed","27183","slider"),("Field Asymmetry","0.350","slider"),("Pupil Irregularity","0.420","slider"),("Chromatic Asymmetry","0.550","slider"),("Transmission Unevenness","0.300","slider")]),
 ("advanced","Advanced","Advanced Responses",[("Highlight Knee","0.700","slider"),("Field Onset","0.350","slider"),("Field Falloff","0.720","slider"),("Defocus Onset","0.080","slider"),("Defocus Falloff","0.520","slider")]),
 ("depth","Advanced","Depth Input",[("Depth Interpretation","Near Black","select"),("Input Near","0.000","slider"),("Input Far","1.000","slider"),("Focus Depth","0.500","slider"),("Depth Edge Protection","1.000","slider"),("Depth Edge Softness","0.500","slider")]),
 ("blend","Blend","Blend",[("Blend","1.000","slider")]),
]

descriptions = {
"presets":("Load, select and save Lens Debaser presets.","Load opens a .ldbpreset file and adds the presets in its folder to the Preset menu. Choose a name from the menu to apply it. Save writes the visible lens settings to a new .ldbpreset file."),
"processing":("Tell Lens Debaser how to interpret its input and choose a diagnostic output.","Input Working Space must match the image entering the node. Diagnostic View replaces the normal output with one of the inspection views described below. Return it to Off for the finished image."),
"capture":("Let focal length, aperture, gate and focus distance influence compatible optical responses.","Capture Influence is the master amount. At zero, the other Capture controls are descriptive but do not alter the image."),
"look":("Apply broad optical personalities with a small set of controls.","Character adds general optical complexity. Vintage Bias emphasizes softer, warmer and less corrected behavior. Vintage Caricature increases that character. Exotic Bias emphasizes unusual distortion and aberration. Classic 2x Anamorphic Bias adds a coordinated anamorphic character. Look Influence controls the combined strength of this group."),
"geometry":("Model barrel, pincushion and moustache distortion around an adjustable optical center.","Primary Distortion handles the broad bend, Secondary adds higher-order curvature, and Moustache creates a direction-changing wave toward the edge."),
"field-shape":("Shape where off-axis effects develop.","Field Center positions the response. Swirl twists it around that center, while Field Aspect and Field Rotation make the response elliptical and change its orientation."),
"focus-field":("Create non-flat focus and directional edge character.","Corner Detail Loss provides broad edge softening. Astigmatism separates radial and tangential response; Field Curvature and the two Smear controls shape focus and detail away from the center."),
"detail":("Adjust perceptual MTF character without acting like a generic sharpen filter.","Microcontrast affects broader local contrast, Fine Detail affects smaller structure, and sagittal/tangential controls create directional transfer differences toward the field edge."),
"chromatic":("Add lateral edge separation and depth-sensitive longitudinal color fringing.","Red and Blue Fringing are lateral offsets. Longitudinal Amount and Radius create differently colored near/far defocus and do not depend on the lateral controls."),
"anamorphic":("Add specifically anamorphic field shape, geometry, aberration and highlight streak behavior.","Anamorphic Field coordinates the full-field response. Distortion and Aberration remain independently adjustable. Flare Amount, Radius, Threshold and Color control the highlight streak response."),
"aperture":("Reconstruct defocused highlights with a chosen pupil footprint.","Response is the amount and Radius is footprint size. Polygon exposes blade controls. Cat-Eye deforms off-axis pupils; Pupil Aspect is active for oval pupils and whenever Cat-Eye is nonzero."),
"vignette":("Combine three distinct forms of edge attenuation.","Natural is smooth illumination falloff, Optical is pupil/field shading, and Mechanical is a harder obstruction-like cutoff."),
"image-circle":("Define the lens-coverage boundary used by Mechanical Vignette.","Size controls coverage, Aspect makes it elliptical and Softness controls the boundary transition. These controls have no visible effect while Mechanical Vignette is zero."),
"bloom":("Spread highlight energy into a soft luminous neighborhood.","Amount is energy, Threshold chooses qualifying highlights, Radius sets reach, and Bloom Stretch makes the spread directional."),
"glare-halo":("Build veiling glare and spherical-aberration halos.","Glare is broad colored scatter. Spherical Halo is a smoother highlight envelope. Both are distinct from Bloom and from the asymmetric Coma controls in Advanced."),
"transmission":("Simulate color and tonal behavior caused by glass and coatings.","Transmission Amount mixes the selected transmission color. Density, Contrast and Highlight Softness shape light passage without requiring bloom or glare."),
"off-axis":("Create asymmetric, field-dependent highlight tails.","Coma sets tail strength and direction; its sign swaps orientation. Coma Threshold is the scene-linear highlight level at which the response begins."),
"variation":("Introduce deterministic copy-to-copy imperfection.","Variation Amount is the master and Seed selects a repeatable lens sample. The four components need compatible base effects—such as field curvature, aperture, chromatic aberration or transmission—to vary."),
"advanced":("Refine when optical responses begin and how quickly they develop.","Highlight Knee shapes the transition into highlight scatter. Field Onset and Field Falloff shape off-axis effects. Defocus Onset and Defocus Falloff shape the transition away from the focus plane."),
"depth":("Use a depth map to place focus and control depth-aware optical effects.","Connect a depth map to the Second RGB/Depth Map input. Depth Interpretation sets whether dark or light values are nearer. Input Near and Input Far remap the useful depth range. Focus Depth moves the focus plane. Depth Edge Protection and Depth Edge Softness control transitions at depth boundaries."),
"blend":("Mix the complete processed result with the untouched source.","Blend 0 is the input image; Blend 1 is the full effect. It remains the final control group for predictable finishing."),
}

lens = [
("Warm Dimensional Prime","Warm transmission, gentle edge falloff and restrained glare while preserving a clear center."),
("Classic Panchro Warmth","Organic edge loss, mild aberration, warm glass and restrained halation."),
("Uncoated Golden Age","Lower contrast, warmer transmission, stronger veil, bloom and spherical halo."),
("Seventies Cinema Zoom","Warm, softer, mildly distorted zoom character with unevenness and edge chromatic texture."),
("Swirling Portrait Glass","Curved focus field and controlled swirl designed around centered portrait subjects."),
("Brass Portrait Swirl","A stronger historical portrait treatment with swirl, shaped pupil and optical falloff."),
("Soap Bubble Triplet","Round, outlined defocus highlights with curved field and modest longitudinal color."),
("Dreamy Soft Focus","Broad spherical softness, gentle bloom and veiling glare with reduced microcontrast."),
("Classic Blue 2x Scope","Two-times anamorphic field, oval/cat-eye pupil, edge aberration and blue streak flare."),
("Warm Amber Scope","A gentler 1.55x anamorphic personality with amber flare and warm transmission."),
("Vintage Scope Edge Warp","Strong off-axis anamorphic deformation, edge loss, smears and chromatic separation."),
("Controlled Blue Radiance","Modern, clean detail with controlled blue flare and minimal transmission loss."),
("Cat-Eye Nocturne","Large night-time pupil footprints, pronounced cat-eye deformation and modest coma."),
("Wide-Angle Moustache","Complex wide-angle geometry, edge CA, coverage falloff and radial texture."),
("Asymmetric Rehoused Photo","Mildly warm stills-lens behavior with deterministic decentering and unevenness."),
("Plastic Fantasy Optic","Deliberately extreme distortion, field smearing, color separation and irregular coverage."),
]

root_descriptions = {
"Setup":"Choose presets, define input interpretation, and apply broad capture and look behavior.",
"Optics":"Shape geometry, the optical field, focus transfer, detail, chromatic behavior and anamorphic response.",
"Pupil & Vignette":"Control the aperture footprint, illumination falloff and the lens image-circle boundary.",
"Light":"Model highlight bloom, glare, spherical halos and the tonal or color response of glass transmission.",
"Advanced":"Refine off-axis behavior, deterministic lens variation, response curves and depth-aware processing.",
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
    p=IMG/f"{slug}.webp"
    if p.exists(): return "data:image/webp;base64,"+base64.b64encode(p.read_bytes()).decode()
    return f"images/{slug}.webp"

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
for slug,root,title,_ in groups:
    if root != active_root:
        root_slug=root.lower().replace(" & ", "-").replace(" ", "-")
        sections.append(f'<article class="root-intro" id="root-{root_slug}"><p class="eyebrow">ROOT CONTROL GROUP</p><h2>{root}</h2><p class="lead">{root_descriptions[root]}</p></article>')
        active_root=root
    lead,body=descriptions[slug]
    sections.append(f'<section id="{slug}"><div><p class="eyebrow">{root} / CONTROL GROUP</p><h2>{title}</h2><p class="lead">{lead}</p><p>{body}</p></div><img src="{image_uri(slug)}" alt="Lens Debaser {root} and {title} controls"></section>')
    if slug == "processing":
        sections.append(diagnostic_html)

preset_rows=''.join(f'<tr><th>{n}</th><td>{d}</td></tr>' for n,d in lens)
demo_names=("Capture","Geometry","Field Shape","Focus & Field","Detail Transfer",
            "Chromatic Aberration","Anamorphic","Aperture","Vignette",
            "Image Circle","Bloom","Glare & Halo / Coma","Transmission",
            "Variation","Advanced Responses","Depth Input")
demo_rows=''.join(f'<li><b>{title}</b> — demonstrates the visible effect of this control group.</li>' for title in demo_names)
guide_css="""
:root{--ink:#e5e8ea;--muted:#9aa2a8;--paper:#111315;--card:#1b1e21;--line:#303438;--acid:#d9ff42;--orange:#ff9738}*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;color:var(--ink);background:var(--paper);font:17px/1.65 Inter,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif}header.hero{padding:8vw max(6vw,30px) 7vw;background:#090b0c;color:white;position:relative;overflow:hidden}.hero:after{content:'Ldb';position:absolute;right:-.02em;bottom:-.45em;font-size:32vw;font-weight:900;color:#171a1c;z-index:0}.hero>*{position:relative;z-index:1}.kicker,.eyebrow{text-transform:uppercase;letter-spacing:.18em;font-size:.72rem;font-weight:800;color:var(--orange)}h1{font-size:clamp(3.4rem,9vw,9rem);line-height:.84;max-width:1000px;margin:.22em 0}.hero .intro{max-width:700px;font-size:1.3rem;color:#c9d0d4}.badge{display:block;color:var(--acid);font-weight:800;margin-top:1.5em}.hero-cta{display:inline-block;margin-top:1.1em;padding:.75em 1.05em;border:1px solid var(--orange);color:var(--orange);font-weight:800;text-decoration:none}.hero-cta[aria-disabled="true"]{cursor:default}.menu-bar{position:sticky;top:0;z-index:10;background:#171a1c;border-bottom:1px solid var(--line);padding:10px 5vw}.menu-button{display:flex;align-items:center;gap:11px;background:transparent;color:#eef1f2;border:1px solid #454b50;padding:9px 13px;font:inherit;font-size:.85rem;cursor:pointer}.menu-icon,.menu-icon:before,.menu-icon:after{display:block;width:19px;height:2px;background:currentColor;content:'';transition:.2s}.menu-icon{position:relative}.menu-icon:before{position:absolute;top:-6px}.menu-icon:after{position:absolute;top:6px}.menu-button[aria-expanded="true"] .menu-icon{background:transparent}.menu-button[aria-expanded="true"] .menu-icon:before{top:0;transform:rotate(45deg)}.menu-button[aria-expanded="true"] .menu-icon:after{top:0;transform:rotate(-45deg)}nav{display:none;position:absolute;left:5vw;right:5vw;top:100%;max-height:70vh;overflow:auto;background:#171a1c;border:1px solid var(--line);padding:14px;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:4px}nav.open{display:grid}nav a{color:#c3c9cd;text-decoration:none;font-size:.82rem;padding:8px 10px}nav a:hover,nav a:focus{background:#262a2d;color:white}.wrap{max-width:1300px;margin:auto;padding:70px 5vw}.notice{background:#202428;color:white;padding:28px 34px;border-left:8px solid var(--acid);margin-bottom:50px}.notice b{color:var(--acid)}h2{font-size:clamp(2rem,4vw,4rem);line-height:1;margin:.12em 0 .35em}.lead{font-size:1.25rem;font-weight:650}.root-intro{margin:100px 0 0;padding:42px;border:1px solid var(--line);border-left:8px solid var(--orange);background:var(--card)}section{display:grid;grid-template-columns:minmax(280px,.85fr) minmax(420px,1.15fr);gap:55px;align-items:center;padding:70px 0;border-bottom:1px solid var(--line)}section img{width:100%;border:1px solid #3c4145;border-radius:2px;box-shadow:none;background:#25282c}article{margin:80px 0}.steps{counter-reset:x;display:grid;grid-template-columns:repeat(4,1fr);gap:16px}.steps div{background:var(--card);border:1px solid var(--line);padding:24px;min-height:180px}.steps div:before{counter-increment:x;content:counter(x);display:block;font-weight:900;font-size:2rem;color:var(--orange)}table{width:100%;border-collapse:collapse;background:var(--card);border:1px solid var(--line)}th,td{text-align:left;vertical-align:top;padding:15px;border-bottom:1px solid var(--line)}th{width:30%}.demo-list{columns:2;column-gap:40px}.demo-list li{break-inside:avoid;margin:0 0 14px}.fine{color:var(--muted);font-size:.9rem}footer{background:#090b0c;color:#bbc2c6;padding:60px 6vw;border-top:1px solid var(--line)}@media(max-width:800px){section{grid-template-columns:1fr;gap:25px}.steps{grid-template-columns:1fr}.demo-list{columns:1}.wrap{padding-top:35px}nav{grid-template-columns:1fr 1fr;left:0;right:0}.hero .intro{font-size:1.1rem}}@media(max-width:480px){nav{grid-template-columns:1fr}h1{font-size:3.2rem}.notice{padding:22px}.root-intro{padding:26px}section{padding:45px 0}}@media print{.menu-bar{display:none}section{break-inside:avoid}.hero{padding:50px}.hero:after{display:none}}
"""
guide_css += ":root{--orange:#16cbf6;--acid:#f64116}"
guide_css += """
.hero{display:grid;grid-template-columns:minmax(0,1fr) minmax(180px,340px);gap:clamp(35px,7vw,110px);align-items:center}
.hero-copy{min-width:0}.hero h1 span{display:block}.hero-logo{display:block;width:100%;height:auto;justify-self:end}
.hero-cta{border:0;background:var(--orange);color:#fff}
.disclaimer{padding:34px 38px;border:1px solid #623026;border-left:8px solid var(--acid);background:#211614}.disclaimer h2{font-size:clamp(2rem,4vw,3.2rem)}.disclaimer p:last-child{margin-bottom:0}
@media(max-width:800px){.hero{grid-template-columns:minmax(0,1fr) minmax(110px,25vw);gap:25px}}
@media(max-width:560px){.hero{grid-template-columns:1fr}.hero-logo{width:min(55vw,220px);justify-self:start;grid-row:1}.hero-copy{grid-row:2}}
"""
html=f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Lens Debaser 1.35 — User Guide</title><style>{guide_css}</style></head><body>
<header class="hero"><div class="hero-copy"><p class="kicker">Lens Debaser 1.35 · User guide</p><h1><span>Lens</span><span>Debaser</span><span>OFX</span></h1><p class="intro">Lens Debaser is an Apple-Silicon Metal/OpenFX effect for DaVinci Resolve. It adds the spatial, chromatic, tonal and highlight character associated with cinematic lenses to modern images.</p><p class="intro">Because all cameras are good now. Too good. So I made this for you to debase perfectly good optics in post - because perfect modern optics is for OnlyFans - not for <strong>ABSOLUTE CINEMA!</strong></p><span class="badge">DEBASE PERFECTLY GOOD OPTICS IN POST</span><a class="hero-cta" href="#" aria-disabled="true" onclick="return false;">Get Lens Debaser now</a></div><img class="hero-logo" src="{image_uri('logo')}" alt="Lens Debaser logo"></header><div class="menu-bar"><button class="menu-button" type="button" aria-expanded="false" aria-controls="guide-menu"><span class="menu-icon" aria-hidden="true"></span><span>Guide menu</span></button><nav id="guide-menu"><a href="#disclaimer">Work in Progress</a><a href="#installation">Installation</a>{nav}<a href="#diagnostic-views">Diagnostic Views</a><a href="#catalogue">Preset catalogue</a></nav></div><main class="wrap">
<article id="disclaimer" class="disclaimer"><p class="eyebrow">WORK IN PROGRESS</p><h2>Experimental software</h2><p>Lens Debaser is under active development. Features, controls, presets, results, compatibility and performance may change without notice. Parts of the plugin may break, behave unexpectedly, or not work entirely as described in this guide.</p><p>The software and this guide are provided <b>as is</b> and <b>as available</b>, without warranties of any kind, express or implied. To the fullest extent permitted by applicable law, the authors and contributors accept no liability for loss, damage, interrupted work, corrupted projects, lost media or any other consequence arising from installation or use. Test the plugin on copies of important projects and media.</p></article>
<article id="installation"><p class="eyebrow">INSTALLATION</p><h2>Install the compiled plug-in</h2><p class="lead">The release package contains the ready-built Apple Silicon OpenFX plug-in, its Metal processing library, factory presets, this guide and an installer. Xcode and developer tools are not required.</p><div class="steps"><div><b>Unpack the release</b><br>Double-click the downloaded Lens Debaser ZIP file to extract its folder.</div><div><b>Quit Resolve</b><br>Fully quit DaVinci Resolve before installing or replacing the plug-in.</div><div><b>Run the installer</b><br>Double-click <b>Install Lens Debaser.command</b> and enter the Mac administrator password when requested. If macOS blocks it, Control-click the installer, choose Open, then confirm.</div><div><b>Restart Resolve</b><br>Open Resolve and find Lens Debaser in the OpenFX effects library. The installer also copies the included factory presets into the Lens Debaser preset folder.</div></div><p class="fine"><b>Requirements:</b> an Apple Silicon Mac and DaVinci Resolve or DaVinci Resolve Studio. Installing a newer release automatically saves the previous plug-in bundle in <code>/Library/Application Support/Lens Debaser/Backups</code>.</p></article>
<article><p class="eyebrow">QUICK START</p><h2>A useful result in four moves</h2><div class="steps"><div><b>Add Lens Debaser</b><br>Add Lens Debaser to a node on the Color page.</div><div><b>Match the input</b><br>Choose the Input Working Space that matches the image entering the node.</div><div><b>Choose a starting point</b><br>Load a preset or begin with Clean Slate, then adjust the controls for the shot.</div><div><b>Optional: set the final strength</b><br>Use Blend when you want to mix the complete Lens Debaser result with the original image.</div></div></article>
{''.join(sections)}
<article id="catalogue"><p class="eyebrow">CINEMATIC LENSES</p><h2>Default character presets</h2><p class="lead">Each preset family is available in Subtle, Medium and Caricature strengths.</p><table><thead><tr><th>Family</th><th>Character</th></tr></thead><tbody>{preset_rows}</tbody></table></article>
<article><p class="eyebrow">DEMONSTRATIONS</p><h2>Explore individual control groups</h2><p>The Demonstrations folder contains presets that isolate the major image-forming control groups. Each is available in Subtle, Medium and Caricature strengths.</p><ul class="demo-list">{demo_rows}</ul></article>
<article><p class="eyebrow">DEPTH MAP WORKFLOW</p><h2>Using a depth map on the Color page</h2><ol><li>Create a depth map and connect its RGB output to Lens Debaser's Second RGB/Depth Map input.</li><li>Choose Near Black when darker depth values represent areas nearer to the camera, or Near White when lighter values represent nearer areas.</li><li>Select Diagnostic View → Depth Input to inspect the depth map used by Lens Debaser.</li><li>Return Diagnostic View to Off and move Focus Depth from 0 to 1 to position the focus plane. Adjust Depth Edge Protection and Depth Edge Softness around depth boundaries.</li></ol></article>
<article><p class="eyebrow">PRACTICAL NOTES</p><h2>Performance and troubleshooting</h2><ul><li><b>Aperture processing:</b> larger Response Radius settings and depth-aware aperture processing require more processing time.</li><li><b>Bloom, glare and anamorphic flare:</b> these effects appear where image brightness crosses their Threshold settings.</li><li><b>Advanced Responses:</b> these controls reshape active field, defocus and highlight effects.</li><li><b>Variation:</b> the same Seed produces the same variation pattern.</li><li><b>Difference diagnostic:</b> this view amplifies changes between the original and processed images so subtle effects are easier to see.</li><li><b>Overall strength:</b> use Blend to reduce or increase the complete effect.</li></ul></article>
</main><footer><b>Lens Debaser 1.35</b><br>Apple Silicon · Metal · OpenFX · DaVinci Resolve<br><span class="fine">CC BY-NC-SA 4.0.</span></footer><script>const button=document.querySelector('.menu-button');const menu=document.querySelector('#guide-menu');button.addEventListener('click',()=>{{const open=button.getAttribute('aria-expanded')==='true';button.setAttribute('aria-expanded',String(!open));menu.classList.toggle('open',!open)}});menu.addEventListener('click',event=>{{if(event.target.closest('a')){{menu.classList.remove('open');button.setAttribute('aria-expanded','false')}}}});document.addEventListener('keydown',event=>{{if(event.key==='Escape'){{menu.classList.remove('open');button.setAttribute('aria-expanded','false')}}}});</script></body></html>'''
(DOC/'Lens-Debaser-User-Guide.html').write_text(html)
print(f"Built guide source for {len(groups)} control groups in {DOC}")
