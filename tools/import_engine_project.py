#!/usr/bin/env python3
"""Import a complete original WE project; print the library entry path."""
import argparse
import json
import os
from pathlib import Path
import shutil
import tempfile


def import_project(source, library, item_id, mode="symlink"):
    if mode not in {"copy", "symlink"}:
        raise ValueError("Import mode must be copy or symlink")
    source = Path(source).resolve(strict=True)
    project = json.loads((source / "project.json").read_text(encoding="utf-8-sig"))
    if not isinstance(project, dict):
        raise ValueError("Project metadata must be a JSON object")
    project_type = project.get("type")
    if not isinstance(project_type, str) or project_type.lower() not in {"scene", "web", "video"}:
        raise ValueError("Only Scene, Web and Video projects are supported")
    if not isinstance(item_id, str) or not item_id.isascii() or not item_id.isdecimal():
        raise ValueError("Workshop item ID must be numeric")
    entry = project.get("file")
    if not isinstance(entry, str) or not entry:
        raise ValueError("Project entry file is missing")
    resource = (source / entry.replace("\\", "/")).resolve()
    if not resource.is_relative_to(source):
        raise ValueError("Project entry escapes its directory")
    # Published Scene projects keep file=scene.json in project.json, while
    # Steam delivers that entry and all resources inside scene.pkg.
    packed_scene = project_type.lower() == "scene" and (source / "scene.pkg").is_file()
    if not resource.is_file() and not packed_scene:
        raise ValueError("Project entry file is missing")
    library = Path(library).resolve()
    if mode == "copy" and library.is_relative_to(source):
        raise ValueError("Copy destination must be outside the source project")
    library.mkdir(parents=True, exist_ok=True)
    destination = library / (item_id + ".weproject")
    # Do not overwrite a user-managed real directory. Symlink refresh is atomic.
    if destination.exists() and not destination.is_symlink():
        if mode == "copy" and (destination / "project.json").is_file():
            return destination
        raise ValueError("Destination already contains a real directory")
    temporary = Path(tempfile.mkdtemp(prefix=".we-import-", dir=library))
    try:
        staged = temporary / "project"
        if mode == "copy":
            shutil.copytree(source, staged)
        else:
            staged.symlink_to(source, target_is_directory=True)
        os.replace(staged, destination)
    finally:
        shutil.rmtree(temporary)
    return destination


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source")
    parser.add_argument("library")
    parser.add_argument("item_id")
    parser.add_argument("--mode", choices=["copy", "symlink"], default="symlink")
    args = parser.parse_args()
    try:
        print(import_project(args.source, args.library, args.item_id, args.mode))
    except (OSError, ValueError) as error:
        parser.exit(4, str(error) + "\n")
