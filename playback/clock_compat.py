#!/usr/bin/env python3
"""Supply missing WE system-font files inside an application-owned Wine prefix.

WE opens CSIDL_FONTS/consola.ttf directly, so Wine FontSubstitutes does not
repair this path. The original application and Workshop package stay intact.
The fallback keeps the source font's family metadata: it is not Consolas and
its metrics may differ. Never replace a font already installed by the user.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def prepare_clock_font(prefix: Path, engine: Path) -> dict:
    source = engine / "assets/fonts/RobotoMono-Regular.ttf"
    target = prefix / "drive_c/windows/Fonts/consola.ttf"
    if not prefix.is_dir() or not (prefix / "drive_c/windows").is_dir():
        raise ValueError("Initialize the application-owned Wine prefix first")
    # Keep writes inside the selected prefix even if its Fonts directory was
    # replaced by a symlink. A symlinked existing target is preserved as well.
    if not target.parent.resolve().is_relative_to(prefix.resolve()):
        raise ValueError("Fonts directory escapes the selected Wine prefix")
    if target.exists() or target.is_symlink():
        return {"status": "preserved", "path": str(target)}
    data = source.read_bytes()
    if data[:4] not in (b"\x00\x01\x00\x00", b"OTTO", b"true"):
        raise ValueError("Fallback is not a standalone OpenType/TrueType font")
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        with target.open("xb") as stream:
            stream.write(data)
    except FileExistsError:
        return {"status": "preserved", "path": str(target)}
    return {
        "status": "installed-fallback", "path": str(target),
        "source": str(source), "family": "Roboto Mono",
        "sha256": hashlib.sha256(data).hexdigest(),
        "limitation": "Fallback metrics differ from Microsoft Consolas",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix", required=True, type=Path)
    parser.add_argument("--engine", required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(prepare_clock_font(args.prefix, args.engine), indent=2))
