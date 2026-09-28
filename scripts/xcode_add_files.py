#!/usr/bin/env python3
"""Add source or resource files to HermesMobile.xcodeproj without XcodeGen.

project.yml is out of date with the checked-in project (regenerating drops the
widget extension's Info.plist settings), so new files are added directly:

    pip install pbxproj
    python scripts/xcode_add_files.py --target HermesMobile HermesMobile/Features/Team/TeamScreen.swift
    python scripts/xcode_add_files.py --target HermesMobile HermesMobile/Resources/MockFixtures

Each file lands in the group matching its folder (groups are created as
needed, with folder-relative paths like the rest of the project). Files that
are already in the project are skipped.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from pbxproj import XcodeProject
from pbxproj.pbxextensions import FileOptions

REPO_ROOT = Path(__file__).resolve().parent.parent
PROJECT_PATH = REPO_ROOT / "HermesMobile.xcodeproj" / "project.pbxproj"


def group_for(project: XcodeProject, folder: Path):
    """Return the group for a repo-relative folder, creating missing levels."""
    parent = project.objects[project.objects[project.rootObject].mainGroup]
    for part in folder.parts:
        parent = _child_group(project, parent, part) or project.add_group(part, path=part, parent=parent)
    return parent


def already_added(project: XcodeProject, relative: Path) -> bool:
    try:
        group = group_for_existing(project, relative.parent)
    except LookupError:
        return False
    return any(project.objects[child_id].get("path", None) == relative.name for child_id in group.children)


def group_for_existing(project: XcodeProject, folder: Path):
    parent = project.objects[project.objects[project.rootObject].mainGroup]
    for part in folder.parts:
        match = _child_group(project, parent, part)
        if match is None:
            raise LookupError(part)
        parent = match
    return parent


def _child_group(project: XcodeProject, parent, part: str):
    for child_id in parent.children:
        child = project.objects[child_id]
        if child.isa == "PBXGroup" and part in (child.get("path", None), child.get("name", None)):
            return child
    return None


def expand(raw_paths: list[str]) -> list[Path]:
    paths: list[Path] = []
    for raw in raw_paths:
        relative = Path(raw)
        if relative.is_absolute():
            relative = relative.resolve().relative_to(REPO_ROOT)
        absolute = REPO_ROOT / relative
        if not absolute.exists():
            raise SystemExit(f"missing: {relative}")
        if absolute.is_dir():
            paths.extend(
                sorted(path.relative_to(REPO_ROOT) for path in absolute.rglob("*") if path.is_file() and path.name != ".DS_Store")
            )
        else:
            paths.append(relative)
    return paths


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--target", required=True, help="Target name, e.g. HermesMobile or HermesMobileTests")
    parser.add_argument("paths", nargs="+", help="Repo-relative files or folders (folders add every file inside)")
    args = parser.parse_args()

    project = XcodeProject.load(str(PROJECT_PATH))
    changed = False
    for relative in expand(args.paths):
        if already_added(project, relative):
            print(f"skip (already in project): {relative}")
            continue
        group = group_for(project, relative.parent)
        # The build phase (sources vs resources) follows the file type.
        project.add_file(
            relative.name,
            parent=group,
            tree="<group>",
            target_name=args.target,
            force=True,  # our own already_added() check; pbxproj's chokes on package build files
            file_options=FileOptions(create_build_files=True),
        )
        print(f"added: {relative} -> {args.target}")
        changed = True
    if changed:
        project.save()


if __name__ == "__main__":
    main()
