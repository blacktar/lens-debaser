#!/usr/bin/env python3
"""Build the public Lens Debaser preset schema from the OFX control table."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "src/ofx/LensDebaserPlugin.cpp"
OUTPUT = ROOT / "preset-authoring/Lens-Debaser-Preset-Schema.json"


def number(token: str) -> float:
    return float(token.strip())


def group_for(control_id: str) -> str:
    if control_id.startswith("final"):
        return "Final Framing"
    if control_id.startswith("capture"):
        return "Capture"
    if control_id.startswith("look"):
        return "Look"
    if control_id in {"fieldAspect", "fieldRotation", "swirl", "responseFieldOnset", "responseFieldFalloff"}:
        return "Field Shape"
    if control_id in {"cornerSharpnessLoss", "fieldCurvature", "astigmatism", "radialSmear", "tangentialSmear"}:
        return "Focus & Field"
    if control_id in {"microContrast", "fineDetail", "detailEdgeFalloff", "sagittalDetail", "tangentialDetail", "detailScale"}:
        return "Detail Transfer"
    if control_id in {"lateralCARed", "lateralCABlue", "longitudinalCA", "longitudinalCARadius", "chromaticFieldOnset", "chromaticFieldFalloff"}:
        return "Chromatic Aberration"
    if control_id.startswith("anamorphic"):
        return "Anamorphic"
    if control_id in {"depthNear", "depthFar", "depthFocus", "responseDefocusOnset", "responseDefocusFalloff", "responseScatterEdgeProtection", "depthEdgeSoftness"}:
        return "Depth Input"
    if control_id.startswith("aperture") or control_id.startswith("opticalDrift"):
        return "Aperture & Bokeh"
    if control_id.startswith("imageCircle"):
        return "Image Circle"
    if control_id.startswith("vignette"):
        return "Vignette"
    if control_id.startswith("bloom"):
        return "Bloom"
    if control_id.startswith("glare") or control_id == "sphericalHalo":
        return "Glare & Halo"
    if control_id.startswith("transmission"):
        return "Transmission"
    if control_id == "responseHighlightKnee":
        return "Highlight Response"
    if control_id.startswith("variation"):
        return "Variation"
    if control_id in {"frontHaze", "cleaningMarks", "scratchAmount", "scratchDirection", "damageScale", "coatingWear", "coatingWearScale", "damageSeed"}:
        return "Front Element Wear"
    if control_id.startswith("internalDirt"):
        return "Internal Element Contamination"
    if control_id.startswith("refractive"):
        return "Refractive Irregularity"
    if control_id.startswith("prism"):
        return "Prism Refraction"
    if control_id in {"coma", "comaThreshold"}:
        return "Off-Axis Character"
    if control_id == "effectBlend":
        return "Blend"
    return "Geometry"


def parse_double_specs(text: str) -> dict[str, dict]:
    start = text.index("const DoubleSpec kSpecs[] = {")
    end = text.index("\n\nstruct Preset", start)
    block = text[start:end]
    pattern = re.compile(
        r'\{\s*"([^"]+)",\s*"([^"]+)",\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*((?:"(?:[^"\\]|\\.)*"\s*)+)\}(?:,|(?=\s*\}))',
        re.S,
    )
    controls: dict[str, dict] = {}
    for match in pattern.finditer(block):
        control_id, label, default, minimum, maximum, step, hint_blob = match.groups()
        hint = "".join(bytes(s, "utf-8").decode("unicode_escape") for s in re.findall(r'"((?:[^"\\]|\\.)*)"', hint_blob))
        integer = number(step) >= 1 and all(number(x).is_integer() for x in (default, minimum, maximum, step))
        controls[control_id] = {
            "label": label,
            "group": group_for(control_id),
            "type": "integer" if integer else "number",
            "default": int(number(default)) if integer else number(default),
            "minimum": int(number(minimum)) if integer else number(minimum),
            "maximum": int(number(maximum)) if integer else number(maximum),
            "step": int(number(step)) if integer else number(step),
            "description": hint,
        }
    if len(controls) < 80:
        raise RuntimeError(f"Parsed only {len(controls)} double controls; source format may have changed")
    return controls


def add_special_controls(controls: dict[str, dict]) -> None:
    controls["finalFramingMode"] = {"label": "Auto Fill Frame", "group": "Final Framing", "type": "integer", "ui_type": "checkbox", "default": 0, "minimum": 0, "maximum": 1, "step": 1, "description": "0 disables automatic edge cropping; 1 enables it. Adjust Auto is active only at 1; Manual Crop only at 0. Both adjustments default to zero and retain independent values."}
    choices = {
        "effectSize": ("Effect Size", "Input & Diagnostics", ["Frame Relative", "Fixed Pixels"], 0),
        "projectionModel": ("Projection Model", "Projection", ["Off", "Equidistant", "Stereographic"], 0),
        "projectionFraming": ("Projection Framing", "Projection", ["Fill Frame", "Balanced", "Preserve Centre Scale"], 1),
        "apertureShape": ("Aperture Shape", "Aperture & Bokeh", ["Circular", "Polygon", "Oval / Anamorphic"], 0),
        "apertureBladeCount": ("Blade Count", "Aperture & Bokeh", list(range(3, 17)), 6),
        "depthMode": ("Depth Interpretation", "Depth Input", ["Depth-Free", "Near White", "Near Black", "Linear Camera Z", "Inverse Z / Disparity", "Logarithmic Z"], 0),
        "captureGate": ("Gate / Capture Format", "Capture", ["Full Frame Open Gate 36 x 24", "Super 35 24.89 x 18.66", "APS-C 23.6 x 15.7", "Micro Four Thirds 17.3 x 13", "65mm 54.12 x 25.58", "Super 16mm 12.52 x 7.41", "16mm 10.26 x 7.49", "8mm 4.8 x 3.5", "Super 8mm 5.79 x 4.01", "Smartphone (Approx.) 9.8 x 7.3", "Full Frame + 1.33x Anamorphic", "Full Frame + 1.55x Anamorphic", "Full Frame + 2x Anamorphic"], 0),
        "prismDistribution": ("Prism Distribution", "Prism Refraction", ["Linear Edge", "Uniform", "Bilateral / Axis", "Radial Field", "Inverse Field"], 0),
        "opticalDriftMode": ("Drift Direction", "Aperture & Bokeh", ["Radial", "Tangential", "Directed"], 0),
    }
    for key, (label, group, values, default) in choices.items():
        if key == "apertureBladeCount":
            controls[key] = {"label": label, "group": group, "type": "integer", "default": default, "minimum": 3, "maximum": 16, "step": 1, "description": "Whole-number blade count. High counts approach a circular iris."}
        else:
            controls[key] = {"label": label, "group": group, "type": "choice", "default": default, "minimum": 0, "maximum": len(values) - 1, "choices": {str(i): value for i, value in enumerate(values)}}

    for prefix, label, group, defaults in (
        ("opticalCenter", "Optical Center", "Geometry", (.5, .5)),
        ("fieldCenter", "Field Center", "Field Shape", (.5, .5)),
    ):
        for axis, default in zip("XY", defaults):
            controls[prefix + axis] = {"label": f"{label} {axis}", "group": group, "type": "number", "default": default, "minimum": 0, "maximum": 1, "step": .001}

    for prefix, label, group, defaults in (
        ("transmission", "Transmission Color", "Transmission", (1, 1, 1)),
        ("glare", "Glare Color", "Glare & Halo", (1, 1, 1)),
        ("nearFocus", "Near-Focus Color", "Chromatic Aberration", (1, .35, .75)),
        ("farFocus", "Far-Focus Color", "Chromatic Aberration", (.35, 1, .65)),
        ("anamorphicFlare", "Flare Color", "Anamorphic", (.35, .55, 1)),
        ("anamorphicFlareGhost", "Ghost Color", "Anamorphic", (.55, .25, 1)),
    ):
        for channel, default in zip("RGB", defaults):
            controls[prefix + channel] = {"label": f"{label} {channel}", "group": group, "type": "number", "default": default, "minimum": 0, "maximum": 2, "step": .001}


def main() -> None:
    text = SOURCE.read_text()
    controls = parse_double_specs(text)
    add_special_controls(controls)
    layout = (ROOT / 'include/LDBControlLayout.h').read_text()
    parse = lambda block: re.findall(r'\{"([^"]*)","([^"]*)","([^"]*)","([^"]*)"\}', block)
    groups = {gid: label for gid,label,_,_ in parse(layout.split('groups[] = {',1)[1].split('};',1)[0])}
    for cid,group,label,hint in parse(layout.split('controls[] = {',1)[1].split('};',1)[0]):
        if cid in controls:
            controls[cid]['label'] = label
            controls[cid]['group'] = groups[group]
            if hint: controls[cid]['description'] = hint
    version = re.search(r"<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>", (ROOT / "resources/Info.plist").read_text()).group(1)
    schema = {
        "title": "Lens Debaser AI Preset Authoring Schema",
        "schema_version": 1,
        "target_plugin_version": version,
        "preset_format": 2,
        "header": "LensDebaserPreset=2",
        "syntax": {
            "comment_prefix": "#",
            "assignment": "key=value",
            "guidance": "Write only controls intentionally changed from their defaults. Do not serialize Input Working Space or Diagnostic View.",
        },
        "ai_delivery_requirements": {
            "output": "Create and attach a finished downloadable .ldbpreset file; do not require the user to copy source text, use a text editor, rename a file, or run a command.",
            "self_check": "Before delivery, reopen the generated file and verify its header, every key and value, duplicate keys, dependencies, and required second inputs against this schema.",
            "revision": "Deliver every requested revision as a newly named downloadable .ldbpreset so earlier versions remain available for comparison.",
        },
        "controls": dict(sorted(controls.items())),
        "dependencies": [
            {"controls": ["apertureRadius", "apertureShape", "apertureBladeCount", "apertureBladeCurvature", "apertureRotation", "apertureSoftness", "apertureCatEye", "apertureAspect", "apertureBokehSwirl", "aperturePupilShift", "aperturePupilClip", "apertureRimWeight", "opticalDriftAmount", "opticalDriftMode", "opticalDriftAngle"], "requires": {"apertureResponse": "> 0"}, "note": "Aperture shape and Optical Drift controls are opt-in and have no image effect until Aperture Response is active. Optical Drift moves only the energy centre of growing defocus. This is one of the more expensive responses."},
            {"controls": ["longitudinalCARadius", "nearFocusR", "nearFocusG", "nearFocusB", "farFocusR", "farFocusG", "farFocusB"], "requires": {"longitudinalCA": "> 0"}, "note": "Axial color settings shape active longitudinal chromatic aberration."},
            {"controls": ["bloomThreshold", "bloomRadius", "bloomStretch"], "requires": {"bloomEnergy": "> 0"}, "note": "Bloom shaping needs Bloom Energy."},
            {"controls": ["glareThreshold", "glareRadius", "glareColorAmount", "glareR", "glareG", "glareB"], "requires": {"glareEnergy": "> 0"}, "note": "Glare shaping needs Glare Amount."},
            {"controls": ["imageCircleSize", "imageCircleHardness", "imageCircleColorAmount"], "requires": {"vignetteMechanical": "> 0"}, "note": "Image Circle shapes mechanical vignette coverage."},
            {"controls": ["prismDirection", "prismDispersion", "prismEdgeBias", "prismSoftness", "prismDistribution"], "requires": {"prismAmount": "> 0"}, "note": "Prism routing and shaping need Prism Amount. Field Shape positions Bilateral, Radial and Inverse modes."},
            {"controls": ["variationScale", "variationAnisotropy", "variationRotation", "variationSeed"], "requires": {"variationAmount": "> 0"}, "note": "Variation shaping needs Variation Amount."},
            {"controls": ["internalDirtScale", "internalDirtSmear", "internalDirtScatter", "internalDirtSoftness", "internalDirtComplexity", "internalDirtSeed"], "requires": {"internalDirtAmount": "> 0"}, "note": "Internal contamination detail settings need Internal Dirt Amount."},
            {"controls": ["captureFocalLength", "captureAperture", "captureFocusDistance", "captureGate"], "requires": {"captureInfluence": "> 0"}, "note": "Capture remaps compatible active optical responses; it does not create a complete lens treatment by itself."},
            {"controls": ["depthNear", "depthFar", "depthFocus", "responseDefocusOnset", "responseDefocusFalloff", "responseScatterEdgeProtection", "depthEdgeSoftness"], "requires": {"depthMode": "> 0 and a second RGB input"}, "note": "Depth Input modifies depth-aware Aperture Response, longitudinal color, spherical halo, and bloom/glare occlusion; it does not create those responses by itself."},
            {"controls": ["fieldAspect", "fieldRotation", "fieldCenterX", "fieldCenterY", "responseFieldOnset", "responseFieldFalloff"], "requires": {"an affected response": "active"}, "note": "Field Shape routes and gates other spatial responses and may be visually neutral on its own."},
        ],
        "final_framing_guidance": "Final Framing crops the completed optical result. Positive Adjust Auto increases automatic crop, negative reduces it and may reveal unwanted edges. Manual Crop is nonnegative. Both values are retained independently. Leave Auto Fill off and Manual Crop at zero to preserve framing. Cropping enlarges retained detail and can soften insufficient-resolution sources. Auto Fill is approximate, not a guarantee for every extreme distortion or source border.",
        "performance_guidance": [
            "Aperture Response and combined chromatic defocus are the most expensive common paths; add them deliberately.",
            "Geometry, prism, detail transfer, vignette and simple transmission treatments are generally lighter.",
            "Prefer the fewest active responses that express the intended optical character, then validate on moving footage and highlights.",
        ],
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(schema, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote {len(controls)} controls to {OUTPUT}")


if __name__ == "__main__":
    main()
