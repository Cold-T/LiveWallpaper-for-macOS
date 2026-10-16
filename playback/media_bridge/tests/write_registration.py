#!/usr/bin/env python3
"""Write, never import, fixture-only scoped WinRT registrations for review."""
import argparse
from pathlib import Path

CLASSES=('Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager','Windows.Storage.Streams.DataReader')
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--dll',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);parser.add_argument('--mute-fixture-prefix',action='store_true');args=parser.parse_args()
    dll=args.dll.resolve()
    if not dll.is_file():parser.error('DLL must exist')
    value=('Z:'+str(dll).replace('/','\\')).replace('\\','\\\\')
    lines=['Windows Registry Editor Version 5.00','','; Import ONLY into explicitly selected isolated fixture WINEPREFIX.']
    for name in CLASSES:
        lines+=['','[HKEY_LOCAL_MACHINE\\Software\\Microsoft\\WindowsRuntime\\ActivatableClassId\\'+name+']','"DllPath"="'+value+'"']
    if args.mute_fixture_prefix:lines+=['','[HKEY_CURRENT_USER\\Software\\Wine\\Drivers]','"Audio"=""']
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text('\r\n'.join(lines)+'\r\n',encoding='utf-16')
    print(str(args.output.resolve()))
if __name__=='__main__':main()
