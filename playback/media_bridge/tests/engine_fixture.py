#!/usr/bin/env python3
"""Operator-only isolated original engine consumer fixture. Never run by unit tests.
prepare does file copies only; run/register/stop invoke Wine explicitly.
Source prefix must be stopped before prepare. This script never requests Automation.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid

OWNER = 'LiveWallpaper isolated synthetic media consumer v1'
CLASS = 'Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager'
def win(p): return 'Z:' + str(Path(p).resolve()).replace('/', '\\')
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def clone(source, destination):
    # Independent APFS copy, without FileProvider extended-attribute copying.
    # Existing read-only font symlinks are preserved; no hardlinks are created.
    result = subprocess.run(['/bin/cp', '-cRX', str(source), str(destination)], capture_output=True)
    if result.returncode:
        if destination.exists(): shutil.rmtree(destination)
        shutil.copytree(source, destination, symlinks=True, copy_function=shutil.copyfile,
                        ignore=shutil.ignore_patterns('*.mdmp', 'log.txt', 'analysis'))
def state(path):
    path=path.resolve()
    data=json.loads((path/'owner.json').read_text())
    if data.get('owner') != OWNER or data.get('path') != str(path):
        raise SystemExit('refusing unowned state directory')
    return path,data
def environment(path,data):
    rt=Path(data['runtime']); gst=rt/'Frameworks/GStreamer.framework/Versions/1.0'
    env=os.environ.copy()
    for key in list(env):
        if key.startswith(('LWMEDIA_', 'LW_WINE_')) or key == 'DYLD_INSERT_LIBRARIES': env.pop(key)
    env.update(SikarugirAppWine11='1',WINEPREFIX=str(path/'prefix'),
        DYLD_FALLBACK_LIBRARY_PATH=str(gst/'lib')+':'+str(rt/'lib'),
        GST_PLUGIN_SYSTEM_PATH_1_0=str(gst/'lib/gstreamer-1.0'),GST_PLUGIN_PATH_1_0='',
        GST_PLUGIN_SCANNER=str(gst/'libexec/gstreamer-1.0/gst-plugin-scanner'),
        GST_REGISTRY=str(path/'prefix/gstreamer-registry.x86_64.bin'),
        WINEDLLOVERRIDES='d3d11,dxgi,d3d10core,winemetal=b;mscoree,mshtml=',
        WINEDEBUG='-all,err+all',LWMEDIA_SNAPSHOT_PATH=win(path/'session.bin'),
        LWMEDIA_ALLOW_FIXTURE='1',LWMEDIA_TRACE='1')
    icd=rt/'vulkan/icd.d/MoltenVK_icd.json'
    if icd.exists(): env.update(CX_LIBVULKAN=str(rt/'lib/libvulkan.1.dylib'),VK_DRIVER_FILES=str(icd),VK_ICD_FILENAMES=str(icd))
    return env

def stop(path,data):
    env=environment(path,data); server=Path(data['runtime'])/'wine/bin/wineserver'
    result=subprocess.run([str(server),'-k'],env=env,timeout=15)
    if result.returncode not in (0,1): raise RuntimeError('prefix-scoped wineserver -k failed')
    subprocess.run([str(server),'-w'],env=env,check=True,timeout=30)

def verify_sources(data):
    for name,expected in data['sourceHashes'].items():
        if digest(Path(name)) != expected: raise RuntimeError('original source changed: '+name)

def prepare(args):
    root=args.state.resolve()
    if root.exists(): raise SystemExit('state must not already exist')
    runtime=args.runtime.resolve(); prefix=args.source_prefix.resolve(); project=args.project.resolve()
    artifacts=args.artifacts.resolve()
    if project.name != 'project.json' or not project.is_file(): raise SystemExit('project must be an extracted project.json')
    if not (prefix/'system.reg').exists(): raise SystemExit('source prefix is not initialized')
    if not args.source_prefix_stopped: raise SystemExit('operator must stop source prefix first and pass --source-prefix-stopped')
    # Never place state inside copied source; do not resolve symlinks into normal runtime.
    for source in (runtime,prefix,project.parent,artifacts):
        if root == source or source in root.parents: raise SystemExit('state must be outside all source trees')
    root.mkdir(parents=True,mode=0o700)
    protected=[runtime/'engine/config.json',runtime/'engine/wallpaper64.exe',project]
    protected += [p for p in (runtime/'engine').rglob('steam*.dll') if p.is_file()]
    protected += [artifacts/'lwmedia-winrt.dll']
    data={'owner':OWNER,'path':str(root),'runtime':str(runtime),'fixture':True,
          'sourceHashes':{str(p):digest(p) for p in protected},'title':'LW-MEDIA-FIXTURE-'+uuid.uuid4().hex}
    (root/'owner.json').write_text(json.dumps(data,indent=2)+'\n')
    try:
        clone(prefix,root/'prefix'); clone(runtime/'engine',root/'engine'); clone(project.parent,root/'project')
        if (root/'prefix/dosdevices/c:').resolve() != (root/'prefix/drive_c').resolve():
            raise RuntimeError('cloned c: drive points outside isolated prefix')
        (root/'artifacts').mkdir()
        shutil.copy2(artifacts/'lwmedia-winrt.dll',root/'artifacts/lwmedia-winrt.dll')
        config_path=root/'engine/config.json'; config=json.loads(config_path.read_text())
        changed=0
        for profile in config.values():
            if not isinstance(profile,dict) or not isinstance(profile.get('general'),dict): continue
            user=profile['general'].setdefault('user',{})
            user.update(mediaintegration=True,videoaudiooutput=False,hasshownwelcomedialog=True)
            changed+=1
        if not changed: raise RuntimeError('no original engine config profile found')
        config_path.write_text(json.dumps(config,ensure_ascii=False,indent=2)+'\n')
        dll=win(root/'artifacts/lwmedia-winrt.dll').replace('\\','\\\\')
        registry='Windows Registry Editor Version 5.00\r\n\r\n'
        registry+='[HKEY_LOCAL_MACHINE\\Software\\Microsoft\\WindowsRuntime\\ActivatableClassId\\'+CLASS+']\r\n'
        registry+='"DllPath"="'+dll+'"\r\n\r\n'
        registry+='[HKEY_LOCAL_MACHINE\\Software\\Microsoft\\WindowsRuntime\\ActivatableClassId\\Windows.Storage.Streams.DataReader]\r\n"DllPath"="'+dll+'"\r\n\r\n'
        # Scoped Wine audio shutdown prevents any sound before control messages run.
        registry+='[HKEY_CURRENT_USER\\Software\\Wine\\Drivers]\r\n"Audio"=""\r\n'
        (root/'register-fixture.reg').write_text(registry,encoding='utf-16')
        subprocess.run([sys.executable,str(Path(__file__).with_name('write_fixture.py')),'--output',str(root/'session.bin'),'--generation','1','--phase','A'],check=True)
        verify_sources(data)
        print(json.dumps({'state':str(root),'fixture':True,'wineExecuted':False,'configProfiles':changed}))
    except BaseException:
        # Preserve evidence and ownership marker so operator can explicitly cleanup.
        raise

def main():
    p=argparse.ArgumentParser(description=__doc__); p.add_argument('action',choices=['prepare','register','run','stop','cleanup','verify'])
    p.add_argument('--state',type=Path,required=True); p.add_argument('--runtime',type=Path)
    p.add_argument('--source-prefix',type=Path); p.add_argument('--source-prefix-stopped',action='store_true')
    p.add_argument('--project',type=Path); p.add_argument('--artifacts',type=Path)
    p.add_argument('--seconds',type=int,default=60); p.add_argument('--width',type=int,default=1470); p.add_argument('--height',type=int,default=956)
    args=p.parse_args()
    if args.action=='prepare':
        if not all((args.runtime,args.source_prefix,args.project,args.artifacts)): p.error('prepare requires runtime/source-prefix/project/artifacts')
        return prepare(args)
    root,data=state(args.state)
    if args.action=='verify': verify_sources(data); print('original_source_hashes_unchanged=true'); return
    if args.action=='cleanup':
        stop(root,data); verify_sources(data)
        # Remove only marked private copies, preserve logs/fixture/hash evidence.
        for name in ('prefix','engine','project','artifacts'):
            target=root/name
            if target.is_symlink(): raise RuntimeError('unexpected state symlink')
            if target.exists(): shutil.rmtree(target)
        print('private_prefix_engine_project_removed=true'); return
    if args.action=='stop': return stop(root,data)
    env=environment(root,data); wine=Path(data['runtime'])/'wine/bin/wine'
    if args.action=='register':
        verify_sources(data)
        subprocess.run([str(wine),'reg.exe','import',win(root/'register-fixture.reg')],cwd=root,env=env,check=True,timeout=60)
        (root/'registered').write_text('fixture-only\n'); return
    if not (root/'registered').exists(): p.error('run requires explicit register step')
    if not 1<=args.seconds<=600: p.error('seconds must be1..600')
    verify_sources(data)
    command=[str(wine),'wallpaper64.exe','-silent','-control','openWallpaper','-file',win(root/'project/project.json'),'-playInWindow',data['title'],'-borderless','-width',str(args.width),'-height',str(args.height),'-x','0','-y','0']
    try:
        with (root/'engine-consumer.log').open('wb') as log:
            process=subprocess.Popen(command,cwd=root/'engine',env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
            (root/'run.json').write_text(json.dumps({'pid':process.pid,'fixture':True,'seconds':args.seconds},indent=2)+'\n')
            deadline=time.monotonic()+args.seconds
            while time.monotonic()<deadline:
                # Engine launcher may exit while child renderer remains alive.
                time.sleep(.2)
    finally:
        stop(root,data); verify_sources(data)
    print('fixture_run_stopped=true; inspect engine-consumer.log and private engine/log.txt')

if __name__=='__main__': main()
