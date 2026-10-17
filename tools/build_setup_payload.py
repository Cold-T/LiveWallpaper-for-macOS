#!/usr/bin/env python3
"""Create the engine-free, pinned first-launch runtime payload (developer tool)."""
import argparse, hashlib, json, subprocess, tarfile, tempfile
from pathlib import Path
ENGINE_SHA = '40e2ce021e9352324fadb3b8f72b8ba2a7ee95b71cc571d5b9f84be75cd993b0'
RUNTIME_ENTRIES = ('wine','lib','Frameworks','WinePlayer.app','vulkan','desktop_window_bridge.dylib','window-playback-control.exe')
ENGINE_ENTRIES = ('wallpaper64.exe','wallpaper32.exe','version.json','assets','bin','plugins','thirdparty','ui','locale','distribution','projects/defaultprojects','projects/templates','ChromaAppInfo.xml','installer.exe','launcher.exe')
def sha(p):
    with open(p,'rb') as f: return hashlib.file_digest(f,'sha256').hexdigest()
def inventory(root):
    files, links = {}, {}
    for p in sorted(root.rglob('*')):
        if p.is_symlink():
            if p.readlink().is_absolute() or not p.resolve().is_relative_to(root):
                raise ValueError(f'Runtime link escapes package: {p}')
            links[str(p.relative_to(root))] = str(p.readlink())
        elif p.is_file(): files[str(p.relative_to(root))] = sha(p)
    return files,links
def build(runtime,engine,output):
    runtime,engine,output = (Path(x).resolve() for x in (runtime,engine,output))
    for source in (runtime,engine):
        if output.is_relative_to(source) or source.is_relative_to(output): raise ValueError('Output overlaps input')
    if sha(engine/'wallpaper64.exe') != ENGINE_SHA: raise ValueError('Expected original Wallpaper Engine 2.8.42')
    output.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='lw-free-runtime-',dir='/private/tmp') as d:
        stage=Path(d)/'runtime';stage.mkdir()
        for name in RUNTIME_ENTRIES:
            subprocess.run(['/bin/cp','-cR',str(runtime/name),str(stage/name)],check=True)
        # Portable runtime contract only; omit machine paths and personal history.
        old=json.loads((runtime/'runtime.json').read_text())
        meta={k:old[k] for k in ('schema','engine_sha256','components','wine_version','dxmt_commit','launch_environment','component_sha256','compatibility_policy','window_control','desktop_bridge')}
        meta['media_fix_receipt']={'receipt':old['media_fix_receipt']['receipt']}
        (stage/'runtime.json').write_text(json.dumps(meta,indent=2))
        files,links=inventory(stage)
        archive=output/'FreeRuntime.tar.gz'
        with tarfile.open(archive,'w:gz',compresslevel=6) as tf:
            for child in sorted(stage.iterdir()): tf.add(child,arcname=child.name)
        engine_files={}
        for name in ENGINE_ENTRIES:
            p=engine/name
            if not p.exists(): raise ValueError(f'Engine component missing: {name}')
            for f in ([p] if p.is_file() else sorted(p.rglob('*'))):
                if f.is_symlink(): raise ValueError(f'Engine symlink not supported: {f}')
                if f.is_file(): engine_files[str(f.relative_to(engine))]=sha(f)
        manifest={'schema':1,'runtime_id':'wine11-dxmt186a232-media18','archive_sha256':sha(archive),
                  'archive_bytes':archive.stat().st_size,'runtime_files':files,'runtime_links':links,
                  'engine_version':'2.8.42','engine_sha256':ENGINE_SHA,'engine_files':engine_files,
                  'components':meta['components'],'requires_free_bytes':6*1024**3}
        (output/'SetupRuntime.json').write_text(json.dumps(manifest,indent=2,sort_keys=True))
        print(json.dumps({'archive':str(archive),'bytes':archive.stat().st_size,'runtime_files':len(files),'engine_files':len(engine_files),'sha256':manifest['archive_sha256']}))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--runtime',required=True);p.add_argument('--engine',required=True);p.add_argument('--output',required=True)
    a=p.parse_args();build(a.runtime,a.engine,a.output)
