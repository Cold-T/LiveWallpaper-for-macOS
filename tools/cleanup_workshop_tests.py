#!/usr/bin/env python3
"""Remove completed test downloads, never the user's ordinary wallpaper library.

The journal must explicitly mark a case testing_complete after visual and
functional review. A sustained Wine window alone does not complete a case.
"""
import argparse
import json
from pathlib import Path
import re
import shutil


def cleanup(items, downloads, library, apply=False):
    downloads, library = Path(downloads).resolve(), Path(library).resolve()
    plan = []
    seen = set()
    for item in items:
        if item.get("testing_complete") is not True:
            continue
        key = str(item["id"])
        if not re.fullmatch(r"[0-9]{6,20}", key):
            raise ValueError("Invalid Workshop ID")
        if key in seen:
            raise ValueError(f"Duplicate completed Workshop ID: {key}")
        seen.add(key)
        source = downloads / key
        entry = library / (key + ".weproject")
        if source.is_symlink() or source.resolve().parent != downloads:
            raise ValueError(f"Download escapes test root: {key}")
        if source.exists() and not source.is_dir():
            raise ValueError(f"Test download is not a directory: {key}")
        if entry.exists() or entry.is_symlink():
            if not entry.is_symlink() or entry.resolve() != source.resolve():
                raise ValueError(f"Library entry is not the test-owned import: {key}")
        plan.append((item, source, entry))
    # Validate every path before deleting anything in the batch.
    result = []
    for item, source, entry in plan:
        existed = source.is_dir() or entry.is_symlink()
        if apply:
            if entry.is_symlink():
                entry.unlink()
            if source.is_dir():
                shutil.rmtree(source)
            item["cleanup"] = "deleted" if existed else "already_absent"
        result.append({"id":str(item["id"]), "download":str(source), "library_entry":str(entry),
                       "action":"deleted" if apply and existed else "already_absent" if apply else "planned"})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("journal", type=Path)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    work = root / "build/workshop-tests"
    journal = args.journal.resolve()
    if not journal.is_relative_to(work.resolve()):
        raise ValueError("Cleanup journal must be in this project's private test directory")
    data = json.loads(journal.read_text())
    # Test renderers must be stopped before any completed asset is removed.
    import os
    import time
    for state in (root / "build/state", root / "build/state11", root / "build/error-monitor-state"):
        for status in state.glob("*/window.json"):
            if time.time() - status.stat().st_mtime >= 8:
                continue
            pid = int(json.loads(status.read_text()).get("pid", 0))
            if pid <= 0:
                continue
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                continue
            raise ValueError("Stop the private test renderer before cleanup")
    result = cleanup(data["items"], work / "downloads/steamapps/workshop/content/431960", root / "build/library", args.apply)
    if args.apply:
        temporary = journal.with_suffix(".new.json")
        temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2))
        temporary.replace(journal)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
