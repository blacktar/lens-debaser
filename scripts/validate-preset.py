#!/usr/bin/env python3
"""Validate AI- or hand-authored Lens Debaser preset files."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPOSITORY_SCHEMA = SCRIPT_DIR.parent / "preset-authoring/Lens-Debaser-Preset-Schema.json"
DEFAULT_SCHEMA = (SCRIPT_DIR / "Lens-Debaser-Preset-Schema.json") if (SCRIPT_DIR / "Lens-Debaser-Preset-Schema.json").exists() else REPOSITORY_SCHEMA


def validate(path: Path, schema: dict) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    if path.suffix != ".ldbpreset":
        errors.append("file name must end in .ldbpreset")
    try:
        lines = path.read_text().splitlines()
    except OSError as exc:
        return [str(exc)], warnings
    meaningful = [(i, line.strip()) for i, line in enumerate(lines, 1) if line.strip() and not line.lstrip().startswith("#")]
    if not meaningful or meaningful[0][1] != schema["header"]:
        errors.append(f"first non-comment line must be {schema['header']}")
    values: dict[str, float] = {}
    seen: set[str] = set()
    controls = schema["controls"]
    for line_no, line in meaningful[1:]:
        if "=" not in line:
            errors.append(f"line {line_no}: expected key=value")
            continue
        key, raw = (part.strip() for part in line.split("=", 1))
        if key in seen:
            errors.append(f"line {line_no}: duplicate control {key}")
            continue
        seen.add(key)
        spec = controls.get(key)
        if spec is None:
            errors.append(f"line {line_no}: unknown or non-preset control {key}")
            continue
        try:
            value = float(raw)
        except ValueError:
            errors.append(f"line {line_no}: {key} must be numeric")
            continue
        if not math.isfinite(value):
            errors.append(f"line {line_no}: {key} must be finite")
            continue
        if value < spec["minimum"] or value > spec["maximum"]:
            errors.append(f"line {line_no}: {key}={value:g} is outside {spec['minimum']}..{spec['maximum']}")
        if spec["type"] in {"integer", "choice"} and not value.is_integer():
            errors.append(f"line {line_no}: {key} must be a whole number")
        values[key] = value

    def effective(key: str) -> float:
        return values.get(key, float(controls[key]["default"]))

    dependency_roots = {
        "apertureResponse": ["apertureRadius", "apertureShape", "apertureBladeCount", "apertureBladeCurvature", "apertureRotation", "apertureSoftness", "apertureCatEye", "apertureAspect", "apertureBokehSwirl", "aperturePupilShift", "aperturePupilClip", "apertureRimWeight"],
        "longitudinalCA": ["longitudinalCARadius", "nearFocusR", "nearFocusG", "nearFocusB", "farFocusR", "farFocusG", "farFocusB"],
        "bloomEnergy": ["bloomThreshold", "bloomRadius", "bloomStretch"],
        "glareEnergy": ["glareThreshold", "glareRadius", "glareColorAmount", "glareR", "glareG", "glareB"],
        "vignetteMechanical": ["imageCircleSize", "imageCircleHardness", "imageCircleColorAmount"],
        "prismAmount": ["prismDirection", "prismDispersion", "prismEdgeBias", "prismSoftness", "prismDistribution"],
        "variationAmount": ["variationScale", "variationAnisotropy", "variationRotation", "variationSeed"],
        "internalDirtAmount": ["internalDirtScale", "internalDirtSmear", "internalDirtScatter", "internalDirtSoftness", "internalDirtComplexity", "internalDirtSeed"],
        "captureInfluence": ["captureFocalLength", "captureAperture", "captureFocusDistance", "captureGate"],
    }
    for root, children in dependency_roots.items():
        authored = [child for child in children if child in values and values[child] != controls[child]["default"]]
        if authored and effective(root) == 0:
            warnings.append(f"{', '.join(authored)} will be inactive because {root}=0")
    if effective("depthMode") > 0:
        warnings.append("depthMode requires the Depth Map second RGB input in Resolve")
    if values and all(values[key] == controls[key]["default"] for key in values):
        warnings.append("all serialized controls equal their defaults; this preset is visually neutral")
    return errors, warnings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("preset", nargs="+", type=Path)
    parser.add_argument("--schema", type=Path, default=DEFAULT_SCHEMA)
    args = parser.parse_args()
    schema = json.loads(args.schema.read_text())
    failed = False
    for path in args.preset:
        errors, warnings = validate(path, schema)
        for message in warnings:
            print(f"WARN: {path}: {message}")
        for message in errors:
            print(f"ERROR: {path}: {message}")
        if errors:
            failed = True
        else:
            print(f"PASS: {path}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
