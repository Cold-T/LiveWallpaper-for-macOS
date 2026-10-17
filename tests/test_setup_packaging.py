"""The public archive must match its manifest and cannot carry private engines."""
import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from build_setup_bundle import validate_payload


class SetupPackagingTests(unittest.TestCase):
    def package(self, root, name='runtime.json', link=None, corrupt=False):
        archive = root / 'FreeRuntime.tar.gz'
        contents = b'{}'
        with tarfile.open(archive, 'w:gz') as package:
            item = tarfile.TarInfo(name)
            if link is not None:
                item.type, item.linkname = tarfile.SYMTYPE, link
                package.addfile(item)
            else:
                item.size = len(contents)
                package.addfile(item, io.BytesIO(contents))
        manifest = {'schema': 1, 'archive_bytes': archive.stat().st_size,
                    'archive_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
                    'runtime_files': {} if link else {name: hashlib.sha256(contents).hexdigest()},
                    'runtime_links': {name: link} if link else {}}
        if corrupt:
            manifest['runtime_files'][name] = '0' * 64
        (root / 'SetupRuntime.json').write_text(json.dumps(manifest))

    def test_manifest_matches(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.package(root)
            self.assertEqual(validate_payload(root)['schema'], 1)

    def test_rejects_engine_paths_traversal_links_and_corruption(self):
        for name, link, corrupt in [('engine/wallpaper64.exe', None, False),
                                    ('wine/../../secret', None, False),
                                    ('wine/link', '../../secret', False),
                                    ('wine/link', '/tmp/secret', False),
                                    ('runtime.json', None, True)]:
            with self.subTest(name=name, link=link, corrupt=corrupt), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.package(root, name, link, corrupt)
                with self.assertRaises(ValueError):
                    validate_payload(root)

    def test_online_sources_have_exactly_one_owner(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.package(root)
            (root / 'FreeRuntime.tar.gz').rename(root / 'RuntimeOverlay.tar.gz')
            manifest_path = root / 'SetupRuntime.json'
            manifest = json.loads(manifest_path.read_text())
            manifest.update(schema=2, overlay_files=dict(manifest['runtime_files']),
                            downloads=[{'id': 'wine', 'url': 'https://github.com/example/archive',
                                        'sha256': 'a' * 64, 'bytes': 1}],
                            source_files={'wine/bin/wine': {'archive': 'wine', 'path': 'wswine.bundle/bin/wine'}})
            manifest['runtime_files']['wine/bin/wine'] = 'b' * 64
            manifest_path.write_text(json.dumps(manifest))
            self.assertEqual(validate_payload(root)['schema'], 2)
            manifest['source_files']['runtime.json'] = {'archive': 'wine', 'path': 'runtime.json'}
            manifest_path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, 'exactly one source'):
                validate_payload(root)


if __name__ == '__main__':
    unittest.main()
