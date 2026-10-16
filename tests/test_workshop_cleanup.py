import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("cleanup", Path(__file__).resolve().parents[1]/"tools/cleanup_workshop_tests.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class CleanupTests(unittest.TestCase):
    def test_completed_only_and_preserve_other_library(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary); downloads=root/"downloads"; library=root/"library"
            downloads.mkdir(); library.mkdir()
            for key in ("1000000001","1000000002"):
                source=downloads/key; source.mkdir(); (source/"scene.pkg").write_bytes(b"test-only fixture")
                (library/(key+".weproject")).symlink_to(source)
            unrelated=library/"personal.mp4"; unrelated.write_bytes(b"preserve")
            items=[{"id":"1000000001","testing_complete":True},{"id":"1000000002","testing_complete":False}]
            self.assertEqual(len(module.cleanup(items,downloads,library)),1)
            self.assertTrue((downloads/"1000000001").exists())
            module.cleanup(items,downloads,library,True)
            self.assertFalse((downloads/"1000000001").exists())
            self.assertFalse((library/"1000000001.weproject").is_symlink())
            self.assertTrue((downloads/"1000000002").exists())
            self.assertEqual(unrelated.read_bytes(),b"preserve")

    def test_foreign_import_aborts_batch_before_any_deletion(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary); downloads=root/"downloads"; library=root/"library"
            downloads.mkdir(); library.mkdir(); foreign=root/"original-project"; foreign.mkdir()
            items=[]
            for key in ("1000000001","1000000002"):
                source=downloads/key; source.mkdir()
                (library/(key+".weproject")).symlink_to(source if key.endswith("1") else foreign)
                items.append({"id":key,"testing_complete":True})
            with self.assertRaises(ValueError):module.cleanup(items,downloads,library,True)
            self.assertTrue((downloads/"1000000001").exists())
            self.assertTrue(foreign.exists())

    def test_source_symlink_and_traversal_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary); downloads=root/"downloads"; library=root/"library"
            downloads.mkdir(); library.mkdir(); foreign=root/"original"; foreign.mkdir()
            (downloads/"1000000001").symlink_to(foreign)
            for key in ("1000000001","../original"):
                with self.assertRaises(ValueError):module.cleanup([{"id":key,"testing_complete":True}],downloads,library,True)
            self.assertTrue(foreign.exists())

    def test_duplicate_and_non_directory_abort_before_deletion(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary); downloads=root/"downloads"; library=root/"library"
            downloads.mkdir(); library.mkdir()
            source=downloads/"1000000001"; source.mkdir()
            case={"id":"1000000001","testing_complete":True}
            with self.assertRaises(ValueError):module.cleanup([case,dict(case)],downloads,library,True)
            self.assertTrue(source.is_dir())
            invalid=downloads/"1000000002"; invalid.write_bytes(b"unexpected file")
            with self.assertRaises(ValueError):
                module.cleanup([case,{"id":"1000000002","testing_complete":True}],downloads,library,True)
            self.assertTrue(source.is_dir())
            self.assertEqual(invalid.read_bytes(),b"unexpected file")


if __name__ == "__main__":unittest.main()
