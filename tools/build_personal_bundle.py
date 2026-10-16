#!/usr/bin/env python3
"""Create a local personal all-in-one app from the verified frontend and runtime."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[1]
def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()
def copy(src,dst):
    shutil.copyfile(src,dst);shutil.copymode(src,dst);return dst
def run(*args,**kw):subprocess.run([str(a) for a in args],check=True,**kw)
def validate_paths(frontend, runtime, work, output, runtime_archive=None):
    """Reject overlapping inputs and destinations before creating any files."""
    frontend, runtime, work, output = [Path(p).resolve() for p in (frontend, runtime, work, output)]
    inputs = [frontend, runtime]
    if runtime_archive is not None:
        inputs.append(Path(runtime_archive).resolve())
    for source in inputs:
        if work.is_relative_to(source) or source.is_relative_to(work):
            raise ValueError(f"Bundle work directory overlaps an input: {source}")
        if output.is_relative_to(source) or source.is_relative_to(output):
            raise ValueError(f"Bundle ZIP output overlaps an input: {source}")
    if output.is_relative_to(work) or work.is_relative_to(output):
        raise ValueError("Bundle ZIP output overlaps the work directory")


def verify_archive(archive, critical):
    prior=json.loads((archive.parent/'BundledRuntime.json').read_text())
    if sha(archive) != prior.get('archive_sha256') or prior.get('critical_files') != critical:
        raise ValueError('Reusable runtime archive does not match its receipt and selected runtime')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--frontend',type=Path,required=True);p.add_argument('--runtime',type=Path,required=True)
    p.add_argument('--runtime-archive',type=Path);p.add_argument('--version',required=True);p.add_argument('--work',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();runtime=a.runtime.resolve();work=a.work.resolve()
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', a.version):
        raise ValueError('Version must be a filename-safe build identifier')
    validate_paths(a.frontend, runtime, work, a.output, a.runtime_archive)
    work.mkdir(parents=True,exist_ok=False)
    app=work/'Livewallpaper for macOS.app'
    for entry in runtime.rglob('*'):
        if entry.is_symlink() and not entry.resolve().is_relative_to(runtime):raise ValueError(f'External runtime symlink: {entry}')
    shutil.copytree(a.frontend,app,symlinks=True,copy_function=copy)
    mac=app/'Contents/MacOS';res=app/'Contents/Resources'
    critical=['engine/wallpaper64.exe','desktop_window_bridge.dylib','window-playback-control.exe',
              'WinePlayer.app/Contents/MacOS/wine','wine/lib/wine/x86_64-windows/winegstreamer.dll',
              'wine/lib/wine/x86_64-windows/mfmediaengine.dll','wine/lib/wine/x86_64-unix/winegstreamer.so']
    critical={name:sha(runtime/name) for name in critical}
    if critical['engine/wallpaper64.exe'] != '40e2ce021e9352324fadb3b8f72b8ba2a7ee95b71cc571d5b9f84be75cd993b0':
        raise ValueError('Only the verified original Wallpaper Engine 2.8.42 is supported')
    print('Compressing full verified runtime',flush=True)
    env=dict(os.environ,COPYFILE_DISABLE='1')
    if a.runtime_archive:
        verify_archive(a.runtime_archive, critical)
        copy(a.runtime_archive,res/'PlaybackRuntime.tar.gz')
    else:
        run('/usr/bin/tar','--no-xattrs','-czf',res/'PlaybackRuntime.tar.gz','-C',runtime,'.',env=env)
    archive_sha=sha(res/'PlaybackRuntime.tar.gz')
    (res/'BundledRuntime.json').write_text(json.dumps({'schema':1,'archive_sha256':archive_sha,'critical_files':critical},indent=2)+'\n')
    info=app/'Contents/Info.plist';meta=plistlib.loads(info.read_bytes());meta['CFBundleName']='Livewallpaper for macOS';meta['CFBundleDisplayName']='Livewallpaper for macOS';meta['CFBundleVersion']=a.version;info.write_bytes(plistlib.dumps(meta))
    for script in (res/'tools').glob('*.sh'):
        script.chmod(script.stat().st_mode | 0o111)
    package=ROOT/'playback/patches/source-pool-package'
    if package.exists():
        shutil.copytree(package,res/'playback/patches/source-pool-package',dirs_exist_ok=True,copy_function=copy)
    run('/usr/bin/xattr','-cr',app)
    run('/usr/bin/codesign','--force','--deep','--sign','-',app)
    run('/usr/bin/codesign','--verify','--deep','--strict',app)
    a.output.parent.mkdir(parents=True,exist_ok=True)
    run('/usr/bin/ditto','-c','-k','--norsrc','--keepParent',app,a.output)
    result={'app':str(app),'zip':str(a.output.resolve()),'zip_sha256':sha(a.output),'zip_bytes':a.output.stat().st_size,'runtime_archive_sha256':archive_sha,'critical_files':critical,'minimum_macos':'14.6','architecture':'Apple Silicon arm64','signature':'ad-hoc; deep strict verified','runtime_install':'~/Library/Application Support/LiveWallpaper-Wine/BundledRuntimes/<archive SHA256>','engine_unchanged':True,'wine_or_audio_started_during_build':False}
    (ROOT/'build').mkdir(parents=True,exist_ok=True)
    (ROOT/('build/personal-bundle-v'+a.version+'.json')).write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2),flush=True)
if __name__=='__main__':main()
