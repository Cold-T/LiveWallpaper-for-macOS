#!/usr/bin/env python3
"""Create a clearly labelled synthetic media contract snapshot; no player access."""
import argparse
import base64
import importlib.util
from pathlib import Path
import struct
import zlib

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("fixture_broker",ROOT/"broker.py")
broker=importlib.util.module_from_spec(spec)
spec.loader.exec_module(broker)

def png(phase):
    def chunk(kind,data):
        return struct.pack(">I",len(data))+kind+data+struct.pack(">I",zlib.crc32(kind+data)&0xffffffff)
    pixel=b"\x20\x80\xe0\xff" if phase=="A" else b"\xe0\x60\x20\xff"
    rows=(b"\0"+pixel*8)*8
    return b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",8,8,8,6,0,0,0))+chunk(b"IDAT",zlib.compress(rows))+chunk(b"IEND",b"")

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--output",required=True,type=Path)
    p.add_argument("--generation",required=True,type=int)
    p.add_argument("--phase",choices=("A","B"),default="A")
    p.add_argument("--absent",action="store_true")
    p.add_argument("--command-capabilities",action="store_true",help="advertise synthetic command capabilities; fixture broker still denies actions")
    a=p.parse_args()
    payload={"available":not a.absent,"session":{
        "bundleIdentifier":"fixture.contract.media", "title":"Fixture media "+a.phase,
        "artist":"Contract test only", "album":"Synthetic, no real playback",
        "state":"playing" if a.phase=="A" else "paused", "durationSeconds":240,
        "positionSeconds":10 if a.phase=="A" else 40, "observedUnixSeconds":1700000000+a.generation,
        "artworkBase64":base64.b64encode(png(a.phase)).decode(),"artworkMimeType":"image/png",
        "capabilities":{k:True for k in broker.CAPABILITIES} if a.command_capabilities else {},
    }}
    broker.publish(a.output,payload,a.generation,fixture=True)
    print('{"fixture":true,"appleEventsSent":0}')

if __name__=="__main__":
    main()
