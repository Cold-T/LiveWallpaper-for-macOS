#!/usr/bin/env python3
"""Operator-only controlled original helper startup checks; never auto-run.
Uses an existing exclusive media-bridge test prefix, registers only there, sends
only original read-only empty-blocklist initialization, and always stops it.
No live native broker, AppleEvents, GUI or playback control command is requested.
"""
import argparse
from collections import Counter
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import time

def win(path):return 'Z:'+str(Path(path).resolve()).replace('/','\\')
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('runtime','prefix','helper','artifacts','out'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--mode',choices=['present','transitions'],required=True)
    parser.add_argument('--seconds',type=int,default=18)
    args=parser.parse_args()
    runtime=args.runtime.resolve();prefix=args.prefix.resolve();helper=args.helper.resolve();artifacts=args.artifacts.resolve();out=args.out.resolve()
    if not 12<=args.seconds<=60:parser.error('seconds must be12..60')
    allowed=runtime.parents[1]/'build/media-bridge'
    if not prefix.is_relative_to(allowed) or prefix==allowed:parser.error('prefix must be an isolated test prefix under repository build/media-bridge')
    if not (prefix/'system.reg').is_file():parser.error('existing initialized test prefix required')
    if out.exists():parser.error('output must not already exist')
    if helper.name.lower()!='winrtutil64.exe' or not (helper.parent/'FreeImage64.dll').is_file():parser.error('private original helper + FreeImage64.dll required')
    out.mkdir(parents=True,mode=0o700);snapshot=out/'session.bin';tests=Path(__file__).resolve().parent
    def publish(generation,phase,absent=False):
        command=[sys.executable,str(tests/'write_fixture.py'),'--output',str(snapshot),'--generation',str(generation),'--phase',phase]
        if absent:command.append('--absent')
        subprocess.run(command,check=True,stdout=subprocess.DEVNULL)
    env=os.environ.copy()
    for key in list(env):
        if key.startswith(('LWMEDIA_','LW_WINE_')) or key=='DYLD_INSERT_LIBRARIES':env.pop(key)
    env.update(SikarugirAppWine11='1',WINEPREFIX=str(prefix),DYLD_FALLBACK_LIBRARY_PATH=str(runtime/'Frameworks/GStreamer.framework/Versions/1.0/lib')+':'+str(runtime/'lib'),WINEDEBUG='-all,err+all',WINEDLLOVERRIDES='mscoree,mshtml=',LWMEDIA_SNAPSHOT_PATH=win(snapshot),LWMEDIA_ALLOW_FIXTURE='1',LWMEDIA_TRACE='1')
    wine=runtime/'wine/bin/wine';server=runtime/'wine/bin/wineserver'
    def stop():
        result=subprocess.run([str(server),'-k'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=15)
        if result.returncode not in (0,1):raise RuntimeError('prefix-scoped stop failed')
        subprocess.run([str(server),'-w'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,timeout=30)
    original_hash=sha(helper);dll_hash=sha(artifacts/'lwmedia-winrt.dll');process=None;phases=[]
    try:
        stop()
        registry=out/'fixture.reg'
        subprocess.run([sys.executable,str(tests/'write_registration.py'),'--dll',str(artifacts/'lwmedia-winrt.dll'),'--output',str(registry),'--mute-fixture-prefix'],check=True,stdout=subprocess.DEVNULL)
        with (out/'register.log').open('wb') as log:subprocess.run([str(wine),'reg.exe','import',win(registry)],env=env,cwd=out,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=60)
        publish(1,'A',args.mode=='transitions');started=time.monotonic()
        if args.mode=='present':phases.append({'phase':'A','seconds':0,'beforeHelperStartup':True})
        with (out/'frames.bin').open('wb') as frames,(out/'helper-trace.log').open('wb') as trace:
            process=subprocess.Popen([str(wine),win(artifacts/'lwmedia-helper-consumer-host.exe'),win(helper),str(args.seconds),'--initialize-readonly'],env=env,cwd=out,stdout=frames,stderr=trace)
            while process.poll() is None:
                elapsed=time.monotonic()-started
                if elapsed>args.seconds+20:raise TimeoutError('owned fixture host exceeded deadline')
                text=(out/'helper-trace.log').read_text(errors='replace')
                if args.mode=='transitions':
                    if not phases and 'event_sessions hr=0x00000000' in text and 'readonly_empty_blocklist_sent_once' in text:
                        publish(2,'A');phases.append({'phase':'A','seconds':elapsed})
                    elif len(phases)==1 and elapsed-phases[0]['seconds']>=4:
                        publish(3,'B');phases.append({'phase':'B','seconds':elapsed})
                time.sleep(.1)
        exit_code=process.returncode
    finally:
        if process and process.poll() is None:process.kill();process.wait(timeout=5)
        stop()
    # Decode only retained original output. Field positions remain positional.
    spec=importlib.util.spec_from_file_location('decoder',tests/'decode_helper_frames.py');decoder=importlib.util.module_from_spec(spec);spec.loader.exec_module(decoder)
    packets=list(decoder.decode((out/'frames.bin').read_bytes()));metadata=[];type_counts=Counter()
    for kind,payload in packets:
        type_counts[kind]+=1
        if kind==1 and len(payload)>=4 and struct.unpack_from('<I',payload)[0]==2:
            fields=[p.decode('utf-8',errors='replace')for p in payload[4:].split(b'\0')[:-1]]
            metadata.append(fields)
    titles=[fields[0]for fields in metadata if fields and fields[0] in ('Fixture media A','Fixture media B')]
    expected=['Fixture media A'] if args.mode=='present' else ['Fixture media A','Fixture media B']
    trace=(out/'helper-trace.log').read_text(errors='replace')
    result={'scope':'original Windows helper fixture startup, not live media or full Scene','mode':args.mode,'fixture':True,'host_exit':exit_code,'phases':phases,'metadataStrings':metadata,'expectedTitles':expected,'observedFixtureTitles':titles,'typeCounts':dict(type_counts),'startupAndNoDuplicateTitlesPassed':titles==expected,'readonlyInitializationSentOnce':trace.count('readonly_empty_blocklist_sent_once')==1,'mediaControlCommandsSent':0,'appleEventsSent':0,'noChangeEventInvokeCount':trace.count('Event.Invoke') if args.mode=='present' else None,'helperSha256Before':original_hash,'helperSha256After':sha(helper),'dllSha256':dll_hash,'ownedChildForcedTermination':'owned_child_timeout_terminate' in trace}
    result['passed']=exit_code==0 and titles==expected and result['readonlyInitializationSentOnce'] and original_hash==sha(helper) and (args.mode!='present' or result['noChangeEventInvokeCount']==0)
    (out/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps(result,ensure_ascii=False))
    return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())
