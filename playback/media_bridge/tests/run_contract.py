#!/usr/bin/env python3
"""Parent/operator-only headless Wine contract runner. Never invoked by build/tests.

Requires a marked fixture snapshot and an explicit isolated prefix; does not
register DLLs, run Wallpaper Engine, invoke AppleEvents or modify shared config.
"""
import argparse
import os
from pathlib import Path
import struct
import subprocess

def windows_path(path):
    return "Z:" + str(Path(path).resolve()).replace("/", "\\")

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix",required=True,type=Path)
    parser.add_argument("--runtime",required=True,type=Path)
    parser.add_argument("--artifacts",required=True,type=Path)
    parser.add_argument("--snapshot",required=True,type=Path)
    parser.add_argument("--watch-ms",type=int,default=0)
    args=parser.parse_args()
    data=args.snapshot.read_bytes()
    if len(data)<24 or data[:8]!=b"LWMEDIA1" or not (struct.unpack_from("<I",data,20)[0]&2):
        parser.error("runner only accepts explicitly marked fixture data")
    if args.watch_ms<0 or args.watch_ms>120000:
        parser.error("watch interval must be between0 and120000ms")
    runtime=args.runtime.resolve();artifacts=args.artifacts.resolve()
    env=os.environ.copy()
    env.pop("DYLD_INSERT_LIBRARIES",None)
    env.update({"SikarugirAppWine11":"1", "WINEPREFIX":str(args.prefix.resolve()),
                "DYLD_FALLBACK_LIBRARY_PATH":str(runtime/"Frameworks/GStreamer.framework/Versions/1.0/lib")+":"+str(runtime/"lib"),
                "WINEDLLOVERRIDES":"mscoree,mshtml=", "WINEDEBUG":"-all,err+all",
                "LWMEDIA_SNAPSHOT_PATH":windows_path(args.snapshot), "LWMEDIA_ALLOW_FIXTURE":"1", "LWMEDIA_TRACE":"1"})
    command=[str(runtime/"wine/bin/wine"), windows_path(artifacts/"lwmedia-contract-probe.exe"),
             windows_path(artifacts/"lwmedia-winrt.dll"), "--watch-ms",str(args.watch_ms)]
    return subprocess.run(command,env=env,cwd=artifacts).returncode

if __name__=="__main__":
    raise SystemExit(main())
