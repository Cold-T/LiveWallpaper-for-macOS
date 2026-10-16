"""Offline build-input validation. Never builds or launches the player."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('bundle_builder', ROOT / 'tools/build_personal_bundle.py')
bundle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)

spec = importlib.util.spec_from_file_location('preview_builder', ROOT / 'tools/build_wine_preview.py')
preview = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview)

spec = importlib.util.spec_from_file_location('runtime_builder', ROOT / 'tools/prepare_wine_runtime.py')
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class RuntimePreparationValidation(unittest.TestCase):
    def test_default_window_control_matches_pinned_helper(self):
        helper = ROOT / 'playback/bin/window-playback-control.exe'
        self.assertEqual(hashlib.sha256(helper.read_bytes()).hexdigest(), runtime.WINDOW_CONTROL_SHA256)


class PreviewResourceValidation(unittest.TestCase):
    def test_excluded_and_deleted_resources_do_not_survive_rebuild(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'source'; source.mkdir()
            (source / 'current.txt').write_text('current')
            (source / 'diagnostics').mkdir()
            (source / 'diagnostics/probe.txt').write_text('excluded')
            target = root / 'target'; target.mkdir()
            (target / 'removed.txt').write_text('stale')
            (target / 'diagnostics').mkdir()
            (target / 'diagnostics/probe.txt').write_text('stale probe')
            preview.copy_resource_tree(source, target, ('diagnostics',))
            self.assertEqual([p.name for p in target.iterdir()], ['current.txt'])

    def test_resource_symlink_is_replaced_without_modifying_its_target(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'source'; source.mkdir()
            (source / 'current.txt').write_text('current')
            external = root / 'external'; external.mkdir()
            (external / 'kept.txt').write_text('keep')
            target = root / 'target'; target.symlink_to(external, target_is_directory=True)
            preview.copy_resource_tree(source, target, ())
            self.assertFalse(target.is_symlink())
            self.assertEqual((external / 'kept.txt').read_text(), 'keep')
            self.assertEqual((target / 'current.txt').read_text(), 'current')


class BundleInputValidation(unittest.TestCase):
    def test_separate_inputs_and_destinations(self):
        bundle.validate_paths('/source/frontend', '/source/runtime', '/stage/build', '/dist/app.zip', '/archive/runtime.tar.gz')

    def test_work_overlap_is_rejected_in_both_directions(self):
        for work in ['/source', '/source/runtime/stage', '/source/frontend/stage', '/archive']:
            with self.subTest(work=work), self.assertRaisesRegex(ValueError, 'overlaps an input'):
                bundle.validate_paths('/source/frontend', '/source/runtime', work, '/dist/app.zip', '/archive/runtime.tar.gz')

    def test_output_cannot_overwrite_inputs_or_include_itself(self):
        for output in ['/source/runtime/app.zip', '/source/frontend/app.zip', '/archive/runtime.tar.gz', '/stage/build/app.zip', '/stage']:
            with self.subTest(output=output), self.assertRaisesRegex(ValueError, 'overlaps'):
                bundle.validate_paths('/source/frontend', '/source/runtime', '/stage/build', output, '/archive/runtime.tar.gz')

    def test_reusable_archive_receipt_and_bytes_must_both_match(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / 'PlaybackRuntime.tar.gz'
            archive.write_bytes(b'fixture archive')
            critical = {'engine/wallpaper64.exe': 'fixture engine'}
            receipt = {'archive_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(), 'critical_files': critical}
            (root / 'BundledRuntime.json').write_text(json.dumps(receipt))
            bundle.verify_archive(archive, critical)
            with self.assertRaisesRegex(ValueError, 'does not match'):
                bundle.verify_archive(archive, {'engine/wallpaper64.exe': 'other engine'})
            archive.write_bytes(b'changed archive')
            with self.assertRaisesRegex(ValueError, 'does not match'):
                bundle.verify_archive(archive, critical)


if __name__ == '__main__':
    unittest.main()
