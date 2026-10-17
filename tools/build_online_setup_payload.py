#!/usr/bin/env python3
"""Build an online setup recipe; vendor bytes stay on their original release hosts."""
import argparse
import hashlib
import json
from pathlib import Path
import tarfile

from build_setup_payload import sha

WINE_URL = 'https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineSikarugir11.0_1.tar.xz'
WINE_SHA = '67e29fb3d74f363af39c69ba11f9b13a79812c5db07cf4748672658e4a200a0e'
FALLBACK_URL = 'https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.0_1/wine-stable-11.0_1-osx64.tar.xz'
FALLBACK_SHA = 'b50dc50ec7f41d58b115a6b685d4d1315ba3c797bd3aa0f49213f2703cb82388'
OVERLAY_FILES = {
    'runtime.json', 'vulkan/icd.d/MoltenVK_icd.json', 'desktop_window_bridge.dylib', 'window-playback-control.exe',
    'WinePlayer.app/Contents/Info.plist',
    *('wine/lib/wine/x86_64-windows/' + name for name in
      ('d3d11.dll', 'dxgi.dll', 'd3d10core.dll', 'winemetal.dll', 'winegstreamer.dll', 'mfmediaengine.dll')),
    'wine/lib/wine/x86_64-unix/winemetal.so',
    'wine/lib/wine/x86_64-unix/winegstreamer.so',
}


def archive_inventory(path):
    cache = Path('/private/tmp') / ('lw-upstream-inventory-' + sha(path) + '.json')
    if cache.exists():
        return json.loads(cache.read_text())
    files = {}
    with tarfile.open(path) as archive:
        for member in archive:
            name = member.name.removeprefix('./').rstrip('/')
            if member.isfile():
                with archive.extractfile(member) as stream:
                    files[name] = hashlib.file_digest(stream, 'sha256').hexdigest()
    cache.write_text(json.dumps(files, sort_keys=True))
    return files


def build(args):
    runtime = Path(args.runtime).resolve()
    output = Path(args.output).resolve()
    if output.is_relative_to(runtime) or runtime.is_relative_to(output):
        raise ValueError('Output overlaps runtime')
    manifest = json.loads(Path(args.manifest).read_text())
    downloads = [('wine', Path(args.wine_archive), WINE_URL, WINE_SHA),
                 ('template', Path(args.template_archive), args.template_url, args.template_sha256),
                 ('fallback', Path(args.fallback_archive), FALLBACK_URL, FALLBACK_SHA)]
    inventories, records = {}, []
    for identifier, path, url, digest in downloads:
        if not url.startswith('https://github.com/') or sha(path) != digest:
            raise ValueError(f'Upstream archive checksum/URL mismatch: {identifier}')
        inventories[identifier] = archive_inventory(path)
        records.append({'id': identifier, 'url': url, 'sha256': digest, 'bytes': path.stat().st_size})
    files = {name: digest for name, digest in manifest['runtime_files'].items()
             if not name.startswith(('lib/wine/', 'WinePlayer.app/Contents/_CodeSignature/'))}
    links = {name: target for name, target in manifest['runtime_links'].items()
             if not name.startswith(('lib/wine/', 'WinePlayer.app/Contents/_CodeSignature/'))}
    # Use the unchanged upstream loader rather than a signature from a local app bundle.
    canonical = 'wswine.bundle/lib/wine/x86_64-unix/wine'
    files['WinePlayer.app/Contents/MacOS/wine'] = inventories['wine'][canonical]
    portable_metadata = Path(args.manifest).parent / 'runtime.json'
    if not portable_metadata.exists():
        with tarfile.open(Path(args.manifest).parent / 'FreeRuntime.tar.gz') as original:
            portable_metadata.write_bytes(original.extractfile('runtime.json').read())
    overlay_paths = {'runtime.json': portable_metadata}
    sources, overlay = {}, {}
    for name, digest in files.items():
        if name in OVERLAY_FILES:
            if sha(overlay_paths.get(name, runtime / name)) != digest:
                raise ValueError(f'Overlay changed since validated manifest: {name}')
            overlay[name] = digest
            continue
        candidates = []
        if name.startswith('wine/'):
            candidates.append(('wine', 'wswine.bundle/' + name[5:]))
        elif name == 'WinePlayer.app/Contents/MacOS/wine':
            candidates.append(('wine', canonical))
        elif name.startswith('Frameworks/'):
            candidates.append(('template', 'Template-1.0.21.app/Contents/' + name))
        elif name.startswith('lib/'):
            candidates.extend([('fallback', 'Wine Stable.app/Contents/Resources/wine/' + name),
                               ('template', 'Template-1.0.21.app/Contents/Frameworks/' + name[4:])])
        elif name.startswith('vulkan/'):
            candidates.append(('template', 'Template-1.0.21.app/Contents/Resources/' + name))
        match = next(((source, path) for source, path in candidates
                      if inventories[source].get(path) == digest), None)
        if match is None:
            # Versioned dylibs may be exposed through an upstream symlink.
            for source, candidate in candidates:
                prefix = candidate.rsplit('/', 1)[0] + '/'
                matches = sorted(path for path, value in inventories[source].items()
                                 if value == digest and path.startswith(prefix))
                if matches:
                    match = (source, matches[0])
                    break
        if match is None:
            raise ValueError(f'No exact upstream source for {name} ({digest})')
        sources[name] = {'archive': match[0], 'path': match[1]}
    if args.licenses:
        for path in sorted(Path(args.licenses).rglob('*')):
            if path.is_symlink():
                raise ValueError('License directory must not contain symlinks')
            if path.is_file():
                name = 'licenses/' + str(path.relative_to(args.licenses))
                files[name] = overlay[name] = sha(path)
                overlay_paths[name] = path
    output.mkdir(parents=True, exist_ok=True)
    archive = output / 'RuntimeOverlay.tar.gz'
    with tarfile.open(archive, 'w:gz', compresslevel=6) as package:
        for name in sorted(overlay):
            package.add(overlay_paths.get(name, runtime / name), arcname=name, recursive=False)
    manifest.update(schema=2, archive_sha256=sha(archive), archive_bytes=archive.stat().st_size,
                    runtime_id='wine11-dxmt186a232-media18-online', downloads=records,
                    source_files=sources, overlay_files=overlay, runtime_files=files, runtime_links=links)
    (output / 'SetupRuntime.json').write_text(json.dumps(manifest, indent=2, sort_keys=True))
    print(json.dumps({'vendor_files': len(sources), 'overlay_files': len(overlay),
                      'runtime_files': len(files), 'bytes': archive.stat().st_size}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('runtime', 'manifest', 'wine-archive', 'template-archive', 'fallback-archive',
                 'template-url', 'template-sha256', 'output'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--licenses')
    build(parser.parse_args())
