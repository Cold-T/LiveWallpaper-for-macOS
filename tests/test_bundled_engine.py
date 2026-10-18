import hashlib
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from build_setup_bundle import copy_engine_components

class BundledEngineTests(unittest.TestCase):
    def test_only_manifest_components_are_copied(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);source=root/'source';source.mkdir();(source/'wallpaper64.exe').write_bytes(b'engine');(source/'config.json').write_bytes(b'private');(source/'user-project').mkdir()
            destination=root/'bundle';copy_engine_components(source,destination,{'wallpaper64.exe':hashlib.sha256(b'engine').hexdigest()})
            self.assertEqual([p.name for p in destination.iterdir()],['wallpaper64.exe'])
            self.assertEqual((destination/'wallpaper64.exe').read_bytes(),b'engine')
    def test_corrupt_external_and_unsafe_inputs_fail(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);source=root/'source';source.mkdir();(source/'file').write_bytes(b'engine');(root/'outside').write_bytes(b'engine');(source/'link').symlink_to(root/'outside')
            for manifest in [{'file':'0'*64},{'missing':'0'*64},{'link':hashlib.sha256(b'engine').hexdigest()},{'../outside':'0'*64}]:
                with self.subTest(manifest=manifest),self.assertRaises(ValueError):copy_engine_components(source,root/'bundle',manifest)
