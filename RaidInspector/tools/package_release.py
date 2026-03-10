#!/usr/bin/env python3
"""Build a release zip that contains RaidInspector and RaidInspectorBridge addons."""

from __future__ import annotations

import argparse
import pathlib
import zipfile
from typing import Iterable

SKIP_DIRS = {"__pycache__", ".git", ".idea", ".vscode"}
SKIP_FILE_SUFFIXES = {".pyc", ".pyo", ".tmp"}
SKIP_FILE_NAMES = {"item_ilvl_cache.json", ".DS_Store"}


def read_version_from_toc(toc_path: pathlib.Path) -> str:
    for line in toc_path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.lower().startswith("## version:"):
            return line.split(":", 1)[1].strip()
    raise ValueError(f"Version not found in TOC: {toc_path}")


def should_skip(path: pathlib.Path, root: pathlib.Path) -> bool:
    rel_parts = path.relative_to(root).parts
    if any(part in SKIP_DIRS for part in rel_parts):
        return True
    if path.name in SKIP_FILE_NAMES:
        return True
    if path.suffix.lower() in SKIP_FILE_SUFFIXES:
        return True
    return False


def iter_files(root: pathlib.Path) -> Iterable[pathlib.Path]:
    for path in sorted(root.rglob("*")):
        if path.is_dir():
            continue
        if should_skip(path, root):
            continue
        yield path


def add_tree(zipf: zipfile.ZipFile, source_dir: pathlib.Path, archive_prefix: str) -> int:
    count = 0
    for path in iter_files(source_dir):
        arcname = pathlib.Path(archive_prefix) / path.relative_to(source_dir)
        zipf.write(path, arcname.as_posix())
        count += 1
    return count


def parse_args() -> argparse.Namespace:
    script_path = pathlib.Path(__file__).resolve()
    default_addons_root = script_path.parents[2]

    parser = argparse.ArgumentParser(description="Build RaidInspector release archive")
    parser.add_argument(
        "--addons-root",
        default=str(default_addons_root),
        help="Path to Interface/AddOns folder",
    )
    parser.add_argument(
        "--output-dir",
        default="",
        help="Output directory for release archive (default: <addons-root>/RaidInspectorRelease)",
    )
    parser.add_argument("--version", default="", help="Override release version")
    parser.add_argument("--name", default="RaidInspector", help="Base archive name")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    addons_root = pathlib.Path(args.addons_root).resolve()
    raidinspector_dir = addons_root / "RaidInspector"
    bridge_dir = addons_root / "RaidInspectorBridge"

    if not raidinspector_dir.exists() or not bridge_dir.exists():
        raise FileNotFoundError("Expected RaidInspector and RaidInspectorBridge under addons root")

    version = args.version or read_version_from_toc(raidinspector_dir / "RaidInspector.toc")
    output_dir = pathlib.Path(args.output_dir).resolve() if args.output_dir else (addons_root / "RaidInspectorRelease")
    output_dir.mkdir(parents=True, exist_ok=True)

    archive_path = output_dir / f"{args.name}-v{version}.zip"

    file_count = 0
    with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as zipf:
        file_count += add_tree(zipf, raidinspector_dir, "RaidInspector")
        file_count += add_tree(zipf, bridge_dir, "RaidInspectorBridge")

    print(f"Created: {archive_path}")
    print(f"Files packed: {file_count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
