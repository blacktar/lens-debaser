#!/usr/bin/env python3
"""Create incremental upload bundles for the externally hosted user guide."""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GUIDE_ROOT = ROOT / "docs" / "user-guide"
STATE_FILE = ROOT / "docs" / "user-guide-published-manifest.json"
OUTPUT_ROOT = ROOT / "releases" / "user-guide-updates"
PUBLISHABLE_SUFFIXES = {".html", ".png", ".webp", ".svg", ".jpg", ".jpeg"}


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def current_manifest() -> dict[str, str]:
    files: dict[str, str] = {}
    for path in sorted(GUIDE_ROOT.rglob("*")):
        if path.is_file() and path.suffix.lower() in PUBLISHABLE_SUFFIXES:
            files[path.relative_to(GUIDE_ROOT).as_posix()] = digest(path)
    return files


def read_published_manifest() -> dict[str, str]:
    if not STATE_FILE.exists():
        raise SystemExit(
            "No published guide baseline exists. After confirming the hosted "
            "guide matches docs/user-guide, run: make guide-publish-record"
        )
    return json.loads(STATE_FILE.read_text(encoding="utf-8"))["files"]


def version() -> str:
    with (ROOT / "resources" / "Info.plist").open("rb") as handle:
        return plistlib.load(handle)["CFBundleShortVersionString"]


def write_state(files: dict[str, str]) -> None:
    payload = {
        "format": 1,
        "purpose": "Files confirmed as manually uploaded to the public user guide",
        "files": files,
    }
    STATE_FILE.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n",
                          encoding="utf-8")


def changes() -> tuple[list[str], list[str]]:
    published = read_published_manifest()
    current = current_manifest()
    changed = sorted(name for name, value in current.items()
                     if published.get(name) != value)
    deleted = sorted(set(published) - set(current))
    return changed, deleted


def bundle() -> None:
    changed, deleted = changes()
    release_version = version()
    destination = OUTPUT_ROOT / f"Lens-Debaser-User-Guide-{release_version}"
    staging = OUTPUT_ROOT / f".Lens-Debaser-User-Guide-{release_version}.staging"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)
    for relative in changed:
        source = GUIDE_ROOT / relative
        target = staging / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
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
    print(f"Created {destination}")
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
