import hashlib
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import build_setup_payload as payload

class EngineInventoryTests(unittest.TestCase):
    def test_empty_json_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'project.json';p.touch()
            with self.assertRaisesRegex(ValueError, 'empty JSON'):payload.sha(p)

    def test_short_read_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'resource.bin';p.write_bytes(b'correct')
            with p.open('rb') as stream:
                stream.seek(7)
                with patch('builtins.open', return_value=stream):
                    with self.assertRaisesRegex(ValueError, 'Incomplete'):payload.sha(p)

    def test_generated_shader_blobs_and_finder_metadata_are_excluded(self):
        with tempfile.TemporaryDirectory() as d:
            r=Path(d);(r/'wallpaper64.exe').write_bytes(b'engine')
            for name in ['assets/project.json','assets/.DS_Store','assets/._project.json','assets/shaders/blobsSM40/local.dxs']:
                p=r/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b'{}')
            with patch.object(payload,'ENGINE_SHA',hashlib.sha256(b'engine').hexdigest()),patch.object(payload,'ENGINE_ENTRIES',('wallpaper64.exe','assets')):
                self.assertEqual(set(payload.engine_inventory(r)),{'wallpaper64.exe','assets/project.json'})
