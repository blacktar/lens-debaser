#!/usr/bin/env python3
"""Create incremental upload bundles for the externally hosted user guide."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import re
import shutil
import stat
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GUIDE_ROOT = ROOT / "docs" / "user-guide"
STATE_FILE = ROOT / "docs" / "user-guide-published-manifest.json"
OUTPUT_ROOT = ROOT / "releases" / "user-guide-updates"
PUBLISHABLE_SUFFIXES = {".html", ".png", ".webp", ".svg", ".jpg", ".jpeg"}


def ensure_visible(path: Path) -> None:
    """Never allow generated upload artifacts to carry macOS hidden flags."""
    if hasattr(os, "chflags"):
        hidden_flags = getattr(stat, "UF_HIDDEN", 0) | getattr(stat, "SF_HIDDEN", 0)
        current_flags = path.stat().st_flags
        if current_flags & hidden_flags:
            os.chflags(path, current_flags & ~hidden_flags)


def file_state(path: Path) -> dict[str, int | str]:
    """Track publishable content exactly; guide assets are distribution files."""
    state = path.stat()
    return {"size": state.st_size, "mtime_ns": state.st_mtime_ns,
            "sha256": file_digest(path)}


def file_digest(path: Path) -> str:
    """Hash a publishable file only when comparing with a legacy hash baseline."""
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def current_manifest() -> dict[str, dict[str, int | str]]:
    files: dict[str, dict[str, int | str]] = {}
    for path in sorted(GUIDE_ROOT.rglob("*")):
        # Finder may create conflict copies such as "image 2.png". They are
        # never referenced by the guide and must not enter an upload delta.
        finder_copy = re.search(r" \d+$", path.stem) is not None
        if (path.is_file() and path.suffix.lower() in PUBLISHABLE_SUFFIXES
                and not finder_copy):
            files[path.relative_to(GUIDE_ROOT).as_posix()] = file_state(path)
    return files


def read_published_manifest() -> dict[str, object]:
    if not STATE_FILE.exists():
        raise SystemExit(
            "No published guide baseline exists. After confirming the hosted "
            "guide matches docs/user-guide, run: make guide-publish-record"
        )
    return json.loads(STATE_FILE.read_text(encoding="utf-8"))["files"]


def version() -> str:
    with (ROOT / "resources" / "Info.plist").open("rb") as handle:
        return plistlib.load(handle)["CFBundleShortVersionString"]


def write_state(files: dict[str, dict[str, int | str]]) -> None:
    payload = {
        "format": 3,
        "purpose": "Files confirmed as manually uploaded to the public user guide",
        "tracking": "Published guide assets tracked by size, modification time and SHA-256",
        "files": files,
    }
    STATE_FILE.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n",
                          encoding="utf-8")


def changes() -> tuple[list[str], list[str]]:
    published = read_published_manifest()
    current = current_manifest()
    changed = []
    for name, value in current.items():
        previous = published.get(name)
        if previous is None:
            changed.append(name)
        elif isinstance(previous, dict):
            if previous != value:
                changed.append(name)
        elif file_digest(GUIDE_ROOT / name) != previous:
            changed.append(name)
    changed.sort()
    deleted = sorted(set(published) - set(current))
    return changed, deleted


def optical_model_changes(baseline_version: str) -> tuple[list[str], list[str]]:
    """Select files whose rendered pixels differ from a released engine."""
    baseline = (ROOT / "outputs" / "experiments" /
                "full-preset-release-comparison" /
                f"released-{baseline_version}")
    if not baseline.is_dir():
        raise SystemExit(f"Missing released render baseline: {baseline}")
    examples = GUIDE_ROOT / "images" / "examples"
    selected = {"Lens-Debaser-User-Guide.html"}
    for current in examples.glob("preset-*-after.png"):
        stem = current.name[len("preset-"):-len("-after.png")]
        released = baseline / f"cinematic-{stem.lower()}.png"
        if not released.is_file():
            raise SystemExit(f"Missing released comparison image: {released.name}")
        if current.read_bytes() != released.read_bytes():
            selected.add(current.relative_to(GUIDE_ROOT).as_posix())
    demo_numbers = {
        "capture":1,"look":2,"geometry":3,"field-shape":4,"focus-field":5,
        "detail":6,"chromatic":7,"anamorphic":8,"aperture":9,"vignette":10,
        "image-circle":11,"bloom":12,"glare-halo":13,"transmission":14,
        "highlight-response":15,"off-axis":16,"variation":17,"depth":18,
        "front-wear":20,"refractive":21,"internal-contamination":24,
        "bokeh-swirl":25,"petzval-field":26,"prism":31,
    }
    demo_presets = {
        int(path.name[:2]): path.stem.lower()
        for path in (ROOT / "presets" / "demonstrations").glob("*.ldbpreset")
    }
    for slug, number in demo_numbers.items():
        for source in ("iso", "optical", "milano1", "milano2", "milano3"):
            current = examples / f"{slug}-{source}-after.png"
            released = baseline / f"demo-{demo_presets[number]}-{source}.png"
            if not current.is_file() or not released.is_file():
                raise SystemExit(f"Missing demo comparison pair: {current.name}")
            if current.read_bytes() != released.read_bytes():
                selected.add(current.relative_to(GUIDE_ROOT).as_posix())
    # Processing is a diagnostic render rather than the ordinary Demo Detail
    # output in the release baseline; include it conservatively.
    selected.add("images/examples/processing-iso-after.png")
    published = read_published_manifest()
    current = current_manifest()
    deleted = sorted(set(published) - set(current))
    return sorted(selected), deleted


def bundle(selected: tuple[list[str], list[str]] | None = None) -> None:
    changed, deleted = selected if selected is not None else changes()
    release_version = version()
    destination = OUTPUT_ROOT / f"Lens-Debaser-User-Guide-{release_version}"
    # Do not use a dot-prefixed staging directory: macOS may propagate its
    # hidden state to descendants even after the directory is renamed.
    staging = OUTPUT_ROOT / f"Lens-Debaser-User-Guide-{release_version}-staging"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)
    ensure_visible(staging)
    for relative in changed:
        source = GUIDE_ROOT / relative
        target = staging / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        ensure_visible(target.parent)
        # copyfile deliberately avoids propagating macOS Finder/BSD metadata.
        shutil.copyfile(source, target)
        ensure_visible(target)
    (staging / "deleted-files.txt").write_text(
        ("\n".join(deleted) + "\n") if deleted else "No hosted files to delete.\n",
        encoding="utf-8",
    )
    (staging / "UPLOAD-INSTRUCTIONS.txt").write_text(
        "Lens Debaser user-guide incremental update\n\n"
        "Upload every HTML or image file in this folder, preserving its relative "
        "path below the public guide directory. Replace the hosted copy when a "
        "file already exists. Review deleted-files.txt and remove only the paths "
        "listed there.\n\n"
        "After checking the public page, run `make guide-publish-record` locally. "
        "Creating this bundle does not advance the published baseline.\n",
        encoding="utf-8",
    )
    if destination.exists():
        shutil.rmtree(destination)
    staging.rename(destination)
    for path in destination.rglob("*"):
        ensure_visible(path)
    ensure_visible(destination)
    archive = OUTPUT_ROOT / f"Lens-Debaser-User-Guide-{release_version}-update.zip"
    if archive.exists():
        archive.unlink()
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED,
                         compresslevel=6) as output:
        for path in sorted(destination.rglob("*")):
            if path.is_file():
                # Archive paths are relative to the hosted guide root. There is
                # deliberately no version-named wrapper directory.
                output.write(path, path.relative_to(destination).as_posix())
    ensure_visible(archive)
    print(f"Created {destination}")
    print(f"Created {archive} (extract directly into the hosted guide root)")
    print(f"Changed/new files: {len(changed)}; hosted deletions: {len(deleted)}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("bundle", "bundle-model", "record", "status"))
    parser.add_argument("--baseline-version", default="1.67")
    args = parser.parse_args()
    if args.command == "record":
        write_state(current_manifest())
        print(f"Recorded current guide as published in {STATE_FILE}")
    elif args.command == "bundle":
        bundle()
    elif args.command == "bundle-model":
        bundle(optical_model_changes(args.baseline_version))
    else:
        changed, deleted = changes()
        print(f"Changed/new files: {len(changed)}")
        for name in changed:
            print(f"  UPDATE {name}")
        print(f"Hosted deletions: {len(deleted)}")
        for name in deleted:
            print(f"  DELETE {name}")


if __name__ == "__main__":
    main()
