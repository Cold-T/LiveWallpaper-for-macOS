#!/usr/bin/env python3
"""Decode captured original winrtutil IPC, not bridge-generated JSON.
Only outer framing and metadata version/string fields have static evidence.
Unknown packet fields remain raw. This program never runs Wine or any media app.
"""
import argparse,json,struct
from pathlib import Path

def decode(data):
    if len(data)%1024: raise ValueError('truncated1024-byte frame capture')
    current=None
    for offset in range(0,len(data),1024):
        frame=data[offset:offset+1024];kind,fragment,length=struct.unpack_from('<III',frame)
        if length>1012 or fragment>3:raise ValueError('invalid frame header')
        part=frame[12:12+length]
        if fragment==0:
            if current:raise ValueError('unfinished fragmented message')
            yield kind,part
        elif fragment==1:
            if current:raise ValueError('nested fragmented message')
            current=(kind,bytearray(part))
        else:
            if not current or kind!=current[0]:raise ValueError('orphan fragment')
            current[1].extend(part)
            if len(current[1])>32*1024*1024:raise ValueError('message exceeds bound')
            if fragment==3:yield current[0],bytes(current[1]);current=None
    if current:raise ValueError('truncated fragmented message')

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('capture',type=Path);args=parser.parse_args()
    for kind,payload in decode(args.capture.read_bytes()):
        row={'scope':'original_helper_fixture_capture','type':kind,'bytes':len(payload)}
        if len(payload)>=4:row['version']=struct.unpack_from('<I',payload)[0]
        if kind==1 and row.get('version')==2:
            # Observed v2 has eight NUL-terminated UTF8 fields, ending in bundle ID.
            # Preserve positional strings; middle field labels remain unaudited.
            strings=payload[4:].split(b'\0')
            row['metadataStrings']=[s.decode('utf-8',errors='replace') for s in strings[:-1]]
        else:row['payloadHex']=payload.hex()
        print(json.dumps(row,ensure_ascii=False))
if __name__=='__main__':main()
