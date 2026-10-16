import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("importer", Path(__file__).resolve().parents[1] / "tools/import_engine_project.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ImportTests(unittest.TestCase):
    def test_scene_keeps_full_directory_and_reimports_atomically(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "with spaces"
            source.mkdir()
            (source / "project.json").write_text(json.dumps({"type": "scene", "file": "scene.pkg"}))
            (source / "scene.pkg").write_bytes(b"PKGV-test")
            (source / "material.tex").write_bytes(b"texture")
            entry = module.import_project(source, root / "library", "123")
            self.assertTrue(entry.is_symlink())
            self.assertEqual((entry / "material.tex").read_bytes(), b"texture")
            self.assertEqual(module.import_project(source, root / "library", "123"), entry)
            self.assertTrue((source / "scene.pkg").exists())

    def test_published_scene_json_entry_is_inside_scene_pkg(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            (source / "project.json").write_text(json.dumps({"type": "scene", "file": "scene.json"}))
            (source / "scene.pkg").write_bytes(b"PKGV-test")
            entry = module.import_project(source, root / "library", "123")
            self.assertTrue((entry / "scene.pkg").is_file())
            self.assertFalse((entry / "scene.json").exists())

    def test_copy_survives_source_removal(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            (source / "project.json").write_text(json.dumps({"type": "web", "file": "index.html"}))
            (source / "index.html").write_text("<html></html>")
            entry = module.import_project(source, root / "library", "123", "copy")
            (source / "index.html").unlink()
            self.assertTrue((entry / "index.html").is_file())

    def test_rejects_executable_and_path_escape(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            (root / "outside").write_text("data")
            for kind, file in [("application", "app.exe"), ("scene", "../outside")]:
                (source / "project.json").write_text(json.dumps({"type": kind, "file": file}))
                with self.assertRaises(ValueError):
                    module.import_project(source, root / "library", "123")

    def test_rejects_malformed_metadata_with_value_error(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            for project in [[], None, "scene", {"type": None}, {"type": []}]:
                with self.subTest(project=project):
                    (source / "project.json").write_text(json.dumps(project))
                    with self.assertRaises(ValueError):
                        module.import_project(source, root / "library", "123")

    def test_rejects_recursive_copy_and_invalid_modes_before_creating_library(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary)
            (source / "project.json").write_text(json.dumps({"type": "web", "file": "index.html"}))
            (source / "index.html").write_text("<html></html>")
            library = source / "library"
            for mode in ["copy", "invalid"]:
                with self.subTest(mode=mode), self.assertRaises(ValueError):
                    module.import_project(source, library, "123", mode)
                self.assertFalse(library.exists())


if __name__ == "__main__": unittest.main()
