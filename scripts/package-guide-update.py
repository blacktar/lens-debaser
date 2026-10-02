#!/usr/bin/env python3
"""Create incremental upload bundles for the externally hosted user guide."""

from __future__ import annotations

import argparse
import json
import os
import plistlib
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


def file_state(path: Path) -> dict[str, int]:
    """Return cheap local change metadata without reading file contents."""
    state = path.stat()
    return {"size": state.st_size, "mtime_ns": state.st_mtime_ns}


def current_manifest() -> dict[str, dict[str, int]]:
    files: dict[str, dict[str, int]] = {}
    for path in sorted(GUIDE_ROOT.rglob("*")):
        if path.is_file() and path.suffix.lower() in PUBLISHABLE_SUFFIXES:
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


def write_state(files: dict[str, dict[str, int]]) -> None:
    payload = {
        "format": 2,
        "purpose": "Files confirmed as manually uploaded to the public user guide",
        "tracking": "Local size and modification time only; no content hashing",
        "files": files,
    }
    STATE_FILE.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n",
                          encoding="utf-8")


def changes() -> tuple[list[str], list[str]]:
    published = read_published_manifest()
    current = current_manifest()
    # Format 1 stored content hashes. Migrate without rereading image data by
    # treating files modified after that manifest was recorded as changed.
    # The next explicit publish record writes the inexpensive format-2 state.
    legacy_cutoff_ns = STATE_FILE.stat().st_mtime_ns
    changed = []
    for name, value in current.items():
        previous = published.get(name)
        if previous is None:
            changed.append(name)
        elif isinstance(previous, dict):
            if previous != value:
                changed.append(name)
        elif value["mtime_ns"] > legacy_cutoff_ns:
            changed.append(name)
    changed.sort()
    deleted = sorted(set(published) - set(current))
    return changed, deleted


def bundle() -> None:
    changed, deleted = changes()
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
    parser.add_argument("command", choices=("bundle", "record", "status"))
    args = parser.parse_args()
    if args.command == "record":
        write_state(current_manifest())
        print(f"Recorded current guide as published in {STATE_FILE}")
    elif args.command == "bundle":
        bundle()
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
