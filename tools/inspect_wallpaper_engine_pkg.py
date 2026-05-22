#!/usr/bin/env python3
"""
Inspect Wallpaper Engine PKGV scene.pkg files.

This only reads package metadata by default. Use --extract-dir to extract files.
"""

from __future__ import annotations

import argparse
import collections
import json
import struct
from pathlib import Path


COMPATIBLE_VIDEO_EXTS = {".mp4", ".mov"}
COMMON_VIDEO_EXTS = {".mp4", ".mov", ".m4v", ".webm", ".avi", ".mkv"}


def read_entries(pkg_path: Path) -> tuple[str, int, list[tuple[str, int, int]]]:
    data = pkg_path.read_bytes()
    pos = 0
    magic_len = struct.unpack_from("<I", data, pos)[0]
    pos += 4
    magic = data[pos : pos + magic_len].decode("ascii", "replace")
    pos += magic_len
    count = struct.unpack_from("<I", data, pos)[0]
    pos += 4

    entries: list[tuple[str, int, int]] = []
    for _ in range(count):
        name_len = struct.unpack_from("<I", data, pos)[0]
        pos += 4
        name = data[pos : pos + name_len].decode("utf-8", "replace")
        pos += name_len
        offset, size = struct.unpack_from("<II", data, pos)
        pos += 8
        entries.append((name, offset, size))

    return magic, pos, entries


def extract(pkg_path: Path, data_base: int, entries: list[tuple[str, int, int]], out: Path) -> None:
    data = pkg_path.read_bytes()
    for name, offset, size in entries:
        target = out / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data[data_base + offset : data_base + offset + size])


def main() -> int:
    parser = argparse.ArgumentParser(description="Inspect a Wallpaper Engine scene.pkg file.")
    parser.add_argument("pkg", type=Path)
    parser.add_argument("--json", action="store_true", help="Print package metadata as JSON.")
    parser.add_argument("--extract-dir", type=Path, help="Extract package contents.")
    args = parser.parse_args()

    magic, data_base, entries = read_entries(args.pkg)
    by_ext: dict[str, list[int]] = collections.defaultdict(lambda: [0, 0])
    for name, _, size in entries:
        ext = Path(name).suffix.lower() or "<none>"
        by_ext[ext][0] += 1
        by_ext[ext][1] += size

    compatible = [
        {"name": name, "size": size}
        for name, _, size in entries
        if Path(name).suffix.lower() in COMPATIBLE_VIDEO_EXTS
    ]
    videos = [
        {"name": name, "size": size}
        for name, _, size in entries
        if Path(name).suffix.lower() in COMMON_VIDEO_EXTS
    ]

    if args.extract_dir:
        extract(args.pkg, data_base, entries, args.extract_dir)

    if args.json:
        print(
            json.dumps(
                {
                    "magic": magic,
                    "data_base": data_base,
                    "entry_count": len(entries),
                    "extensions": {
                        ext: {"count": count, "bytes": total}
                        for ext, (count, total) in sorted(by_ext.items())
                    },
                    "compatible_videos": compatible,
                    "common_videos": videos,
                    "entries": [
                        {"name": name, "offset": offset, "size": size}
                        for name, offset, size in entries
                    ],
                },
                indent=2,
                ensure_ascii=False,
            )
        )
        return 0

    print(f"magic: {magic}")
    print(f"entries: {len(entries)}")
    print(f"data_base: {data_base}")
    print()
    print("extensions:")
    for ext, (count, total) in sorted(by_ext.items(), key=lambda item: (-item[1][1], item[0])):
        print(f"  {ext:8} count={count:3d} bytes={total}")
    print()
    print("compatible videos for current app:")
    if compatible:
        for item in compatible:
            print(f"  {item['size']:10d}  {item['name']}")
    else:
        print("  none")
    print()
    print("all entries:")
    for name, offset, size in entries:
        print(f"  {size:10d}  {offset:10d}  {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
