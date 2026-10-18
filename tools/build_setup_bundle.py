#!/usr/bin/env python3
"""Package setup components, optionally embedding a verified engine file set."""
import argparse, hashlib, json, posixpath, subprocess, tarfile, tempfile, shutil
from build_setup_payload import RUNTIME_ENTRIES
from pathlib import Path

def validate_payload(payload):
    """Verify every archived member before shipping an engine-free runtime."""
    meta = json.loads((payload / 'SetupRuntime.json').read_text())
    if meta.get('schema') not in (1, 2):
        raise ValueError('Unsupported setup manifest schema')
    archive = payload / ('RuntimeOverlay.tar.gz' if meta['schema'] == 2 else 'FreeRuntime.tar.gz')
    with archive.open('rb') as stream:
        if hashlib.file_digest(stream, 'sha256').hexdigest() != meta['archive_sha256']:
            raise ValueError('Payload checksum mismatch')
    if archive.stat().st_size != meta['archive_bytes']:
        raise ValueError('Payload size mismatch')
    files, links, seen = {}, {}, set()
    allowed = {*RUNTIME_ENTRIES, 'runtime.json', 'licenses'}
    with tarfile.open(archive, 'r:gz') as package:
        for member in package:
            name = member.name
            parts = name.split('/')
            if name.startswith('/') or any(p in ('', '.', '..') for p in parts):
                raise ValueError(f'Unsafe archive path: {name}')
            if name in seen or parts[0] not in allowed:
                raise ValueError(f'Unexpected archive member: {name}')
            seen.add(name)
            if member.isfile():
                with package.extractfile(member) as stream:
                    files[name] = hashlib.file_digest(stream, 'sha256').hexdigest()
            elif member.issym():
                target = posixpath.normpath(posixpath.join(posixpath.dirname(name), member.linkname))
                if member.linkname.startswith('/') or target == '..' or target.startswith('../'):
                    raise ValueError(f'Archive link escapes runtime: {name}')
                links[name] = member.linkname
            elif not member.isdir():
                raise ValueError(f'Unsupported archive member: {name}')
    expected_files = meta['overlay_files'] if meta['schema'] == 2 else meta['runtime_files']
    expected_links = {} if meta['schema'] == 2 else meta['runtime_links']
    if files != expected_files or links != expected_links:
        raise ValueError('Archive contents differ from setup manifest')
    if meta['schema'] == 2:
        sources = meta['source_files']
        if set(sources) & set(files) or set(sources) | set(files) != set(meta['runtime_files']):
            raise ValueError('Every runtime file must have exactly one source')
        downloads = {item['id']: item for item in meta['downloads']}
        if len(downloads) != len(meta['downloads']):
            raise ValueError('Duplicate download identifier')
        for item in downloads.values():
            if not item['url'].startswith('https://github.com/') or len(item['sha256']) != 64 or item['bytes'] <= 0:
                raise ValueError('Invalid pinned download')
        for name, source in sources.items():
            for path in (name, source['path']):
                if path.startswith('/') or any(part in ('', '.', '..') for part in path.split('/')):
                    raise ValueError('Unsafe source path')
            if source['archive'] not in downloads:
                raise ValueError('Unknown download identifier')
        if any(meta['runtime_files'].get(name) != digest for name, digest in files.items()):
            raise ValueError('Overlay differs from final runtime')
    return meta


def copy_engine_components(engine, destination, files):
    engine, destination = Path(engine).resolve(), Path(destination)
    if destination.exists() or destination.is_symlink():
        raise ValueError('Engine destination must be empty')
    destination = destination.resolve()
    if not files:
        raise ValueError('Empty engine component list')
    if destination.is_relative_to(engine) or engine.is_relative_to(destination):
        raise ValueError('Engine destination overlaps input')
    # Copy only the verified component set, excluding user projects and settings.
    for name, expected in files.items():
        if name.startswith('/') or any(part in ('', '.', '..') for part in name.split('/')):
            raise ValueError('Unsafe engine component path')
        source = engine / name
        if source.is_symlink() or not source.resolve().is_relative_to(engine) or not source.is_file():
            raise ValueError(f'Missing or external engine component: {name}')
        with source.open('rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != expected:
                raise ValueError(f'Engine component checksum mismatch: {name}')
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        shutil.copymode(source, target)
        with target.open('rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != expected:
                raise ValueError(f'Copied engine component checksum mismatch: {name}')


def build(app,payload,output,engine=None):
    app,payload,output=(Path(x).resolve() for x in (app,payload,output))
    if output.is_relative_to(app) or output.is_relative_to(payload):raise ValueError('Output overlaps input')
    if (app/'Contents/Resources/BundledRuntime.json').exists():raise ValueError('Use the public frontend, not a personal engine bundle')
    if engine is not None and output.is_relative_to(Path(engine).resolve()):
        raise ValueError('Output overlaps engine input')
    meta = validate_payload(payload)
    output.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='lw-setup-package-',dir='/private/tmp') as d:
        stage=Path(d)/'Livewallpaper for macOS.app'
        subprocess.run(['/bin/cp','-cR',str(app),str(stage)],check=True)
        for name in (('RuntimeOverlay.tar.gz' if meta['schema'] == 2 else 'FreeRuntime.tar.gz'), 'SetupRuntime.json'):
            subprocess.run(['/bin/cp','-c',str(payload/name),str(stage/'Contents/Resources'/name)],check=True)
        if engine is not None:
            copy_engine_components(engine, stage/'Contents/Resources/WallpaperEngine', meta['engine_files'])
        subprocess.run(['/usr/bin/xattr','-cr',str(stage)],check=True)
        subprocess.run(['/usr/bin/codesign','--force','--deep','--sign','-',str(stage)],check=True)
        subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(stage)],check=True)
        subprocess.run(['/usr/bin/ditto','-c','-k','--sequesterRsrc','--keepParent',str(stage),str(output)],check=True)
    with open(output,'rb') as f: digest=hashlib.file_digest(f,'sha256').hexdigest()
    output.with_suffix('.sha256').write_text(digest+'  '+output.name+'\n')
    print(output,digest)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--app',required=True);p.add_argument('--payload',required=True);p.add_argument('--output',required=True);p.add_argument('--engine', help='Bundle the verified Wallpaper Engine components')
    a=p.parse_args();build(a.app,a.payload,a.output,a.engine)
