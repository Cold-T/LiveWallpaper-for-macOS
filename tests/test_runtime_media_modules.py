import hashlib
import importlib.util
import json
import plistlib
from unittest.mock import patch
from pathlib import Path
import struct
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('runtime_prepare', Path(__file__).parents[1] / 'tools/prepare_wine_runtime.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def pe(machine=0x8664):
    data = bytearray(512)
    data[:2] = b'MZ'
    struct.pack_into('<I', data, 60, 128)
    data[128:132] = b'PE\0\0'
    struct.pack_into('<H', data, 132, machine)
    struct.pack_into('<H', data, 150, 0x2000)
    struct.pack_into('<H', data, 152, 0x20b)
    return bytes(data)


class MediaModulePreparation(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.output = self.root / 'runtime'
        self.target = self.output / 'wine/lib/wine/x86_64-windows'
        self.target.mkdir(parents=True)
        self.source = self.root / 'candidate.dll'
        self.source.write_bytes(pe())
        self.digest = hashlib.sha256(self.source.read_bytes()).hexdigest()

    def test_verified_module_installed_without_changing_source(self):
        result = module.prepare_media_pe(self.source, self.digest, self.output, 'mfmediaengine.dll')
        self.assertEqual((self.target / 'mfmediaengine.dll').read_bytes(), pe())
        self.assertEqual(self.source.read_bytes(), pe())
        self.assertEqual(result['sha256'], self.digest)

    def test_wrong_hash_preserves_existing_module(self):
        target = self.target / 'mfmediaengine.dll'
        target.write_bytes(b'original')
        with self.assertRaisesRegex(ValueError, 'SHA256'):
            module.prepare_media_pe(self.source, '0' * 64, self.output, 'mfmediaengine.dll')
        self.assertEqual(target.read_bytes(), b'original')

    def test_wrong_architecture_rejected(self):
        self.source.write_bytes(pe(0x14c))
        digest = hashlib.sha256(self.source.read_bytes()).hexdigest()
        with self.assertRaisesRegex(ValueError, 'AMD64'):
            module.prepare_media_pe(self.source, digest, self.output, 'mfmediaengine.dll')
        self.assertFalse((self.target / 'mfmediaengine.dll').exists())

    def test_escaping_module_directory_cannot_modify_source_installation(self):
        external = self.root / 'original-installation'
        external.mkdir()
        (external / 'mfmediaengine.dll').write_bytes(b'original')
        self.target.rmdir()
        self.target.symlink_to(external, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'escapes'):
            module.prepare_media_pe(self.source, self.digest, self.output, 'mfmediaengine.dll')
        self.assertEqual((external / 'mfmediaengine.dll').read_bytes(), b'original')

    def test_gstreamer_pe_requires_matched_unix_selection_before_copy(self):
        output = self.root / 'not-created'
        with self.assertRaisesRegex(ValueError, 'matching Unix'):
            module.prepare(self.root, self.root, self.root, output, self.root,
                           wine_gstreamer_pe=self.source, wine_gstreamer_pe_sha256=self.digest)
        self.assertFalse(output.exists())

    def test_runtime_output_nested_in_input_rejected_before_creation(self):
        output = self.root / "engine" / "prepared"
        with self.assertRaisesRegex(ValueError, 'overlaps'):
            module.prepare(self.root / "engine", self.root / "wine", self.root / "libs",
                           output, self.root / "frameworks/gstreamer")
        self.assertFalse(output.exists())

    def test_component_file_link_is_replaced_without_mutating_input(self):
        original = self.root / 'original.dll'
        original.write_bytes(b'original')
        target = self.target / 'dxgi.dll'
        target.symlink_to(original)
        module.copy_owned_file(self.source, target, self.output)
        self.assertFalse(target.is_symlink())
        self.assertEqual(target.read_bytes(), pe())
        self.assertEqual(original.read_bytes(), b'original')

    def test_component_parent_link_outside_runtime_rejected(self):
        external = self.root / 'external'
        external.mkdir()
        (self.output / 'escaped').symlink_to(external)
        with self.assertRaisesRegex(ValueError, 'escapes'):
            module.copy_owned_file(self.source, self.output / 'escaped/dxgi.dll', self.output)
        self.assertFalse((external / 'dxgi.dll').exists())

    def test_receipt_rejects_mixed_modules_and_missing_selection(self):
        names = ['winegstreamer.dll', 'winegstreamer.so', 'mfmediaengine.dll']
        receipt = self.root / 'receipt.json'
        receipt.write_text(json.dumps({'schema': 1, 'modules': {n: self.digest for n in names}}))
        selections = {n: (self.source, self.digest) for n in names}
        result = module.verify_media_fix_receipt(receipt, selections)
        self.assertEqual(result['receipt']['modules']['winegstreamer.dll'], self.digest)
        selections['winegstreamer.so'] = (self.source, '0' * 64)
        with self.assertRaisesRegex(ValueError, 'mismatch'):
            module.verify_media_fix_receipt(receipt, selections)
        del selections['winegstreamer.so']
        with self.assertRaisesRegex(ValueError, 'all three'):
            module.verify_media_fix_receipt(receipt, selections)

    def test_malformed_receipt_is_explained(self):
        receipt = self.root / 'receipt.json'
        receipt.write_text('[]')
        with self.assertRaisesRegex(ValueError, 'schema 1'):
            module.verify_media_fix_receipt(receipt, {})

    def test_bundle_uses_physical_native_loader_and_adjacent_ntdll(self):
        native = self.output / 'wine/lib/wine/x86_64-unix'
        native.mkdir(parents=True)
        def macho(kind):
            data = bytearray(64)
            struct.pack_into('<IIII', data, 0, 0xfeedfacf, 0x01000007, 3, kind)
            return bytes(data)
        (native / 'wine').write_bytes(macho(2))
        (native / 'wine').chmod(0o755)
        (native / 'ntdll.so').write_bytes(macho(6))
        for name in ['ntdll.dll', 'apisetschema.dll']:
            (self.target / name).write_bytes(pe())
        share = self.output / 'wine/share/wine'
        for name in ['wine.inf', 'nls/locale.nls', 'nls/l_intl.nls', 'nls/normnfc.nls', 'fonts/test.ttf', 'winmd/test.winmd']:
            file = share / name; file.parent.mkdir(parents=True, exist_ok=True); file.write_bytes(name.encode())
            module.os.utime(file, ns=(1234567890123456789, 1234567890123456789))
        with patch.object(module.subprocess, 'run') as run:
            result = module.prepare_player_bundle(self.output)
        app = self.output / 'WinePlayer.app/Contents'
        self.assertEqual((app / 'MacOS/wine').read_bytes(), macho(2))
        self.assertEqual((app / 'MacOS/ntdll.so').read_bytes(), macho(6))
        self.assertTrue((app / 'MacOS/ntdll.so').is_symlink())
        self.assertEqual((app / 'MacOS/ntdll.so').resolve(), (native / 'ntdll.so').resolve())
        self.assertTrue(module.os.path.samefile(app / 'MacOS/ntdll.so', native / 'ntdll.so'))
        self.assertFalse((app / 'Resources/wine').exists())
        self.assertEqual(result['wine_data_directory'], str(share.resolve()))
        self.assertNotEqual((native / 'wine').stat().st_ino, (app / 'MacOS/wine').stat().st_ino)
        self.assertEqual(plistlib.loads((app / 'Info.plist').read_bytes())['CFBundleExecutable'], 'wine')
        self.assertTrue(result['single_core_layout'])
        self.assertFalse(result['strict_signature']['supported'])
        for name in ['ntdll.dll', 'apisetschema.dll']:
            self.assertEqual((self.target / name).read_bytes(), pe())
            self.assertEqual(result['bootstrap_pe_sha256'][name], hashlib.sha256(pe()).hexdigest())
        for file in share.rglob('*'):
            if file.is_file(): self.assertEqual(file.stat().st_mtime_ns, 1234567890123456789)
        self.assertIn('--preserve-metadata=entitlements,flags', run.call_args_list[0].args[0])
        self.assertNotIn('--strict', run.call_args_list[1].args[0])
        self.assertIn('--deep', run.call_args_list[1].args[0])

    def test_bootstrap_pe_rejects_wrong_architecture_and_truncation(self):
        source = self.root / 'bootstrap.dll'
        for data in [pe(0x14c), b'MZ', pe()[:140], b'not a PE']:
            source.write_bytes(data)
            with self.assertRaisesRegex(ValueError, 'AMD64 PE32'):
                module.verify_bootstrap_pe(source)
            self.assertEqual(source.read_bytes(), data)
        source.write_bytes(pe())
        self.assertEqual(module.verify_bootstrap_pe(source), hashlib.sha256(pe()).hexdigest())

    def test_receipted_backend_updates_profiles_preserves_source_and_quality(self):
        source = self.root / 'original-config.json'
        data = {'?installdirectory': 'old', 'existing': {'general': {'user': {
            'videoframework': 'auto', 'videohardwareacceleration': True, 'fps': 60, 'postprocessing': 'enabled'}}},
            'metadata': 'kept'}
        source.write_text(json.dumps(data))
        original = source.read_bytes()
        target = self.output / 'engine/config.json'
        target.parent.mkdir()
        target.symlink_to(source)
        policy = module.configure_engine_file(target, self.output, 'current', media_fix=True, video_hardware_acceleration=False)
        result = json.loads(target.read_text())
        self.assertEqual(policy, {'videoframework': 'mf', 'videohardwareacceleration': False})
        for name in ['existing', 'current']:
            self.assertEqual(result[name]['general']['user']['videoframework'], 'mf')
            self.assertFalse(result[name]['general']['user']['videohardwareacceleration'])
        self.assertEqual(result['existing']['general']['user']['fps'], 60)
        self.assertEqual(result['existing']['general']['user']['postprocessing'], 'enabled')
        self.assertEqual(result['metadata'], 'kept')
        self.assertEqual(source.read_bytes(), original)
        self.assertFalse(target.is_symlink())

    def test_no_receipt_preserves_backend_selection(self):
        target = self.output / 'config.json'
        target.write_text(json.dumps({'current': {'general': {'user': {
            'videoframework': 'auto', 'videohardwareacceleration': True}}}}))
        self.assertIsNone(module.configure_engine_file(target, self.output, 'current'))
        user = json.loads(target.read_text())['current']['general']['user']
        self.assertEqual(user['videoframework'], 'auto')
        self.assertTrue(user['videohardwareacceleration'])

    def test_invalid_config_structure_preserved_on_failure(self):
        target = self.output / 'config.json'
        original = b'{"current": {"general": {"user": "unexpected"}}}'
        target.write_bytes(original)
        with self.assertRaisesRegex(ValueError, 'user settings'):
            module.configure_engine_file(target, self.output, 'current', media_fix=True)
        self.assertEqual(target.read_bytes(), original)

    def test_receipt_without_explicit_hwa_preserves_hardware_choice(self):
        target = self.output / 'config.json'
        target.write_text(json.dumps({'current': {'general': {'user': {
            'videoframework': 'auto', 'videohardwareacceleration': True}}}}))
        policy = module.configure_engine_file(target, self.output, 'current', media_fix=True)
        self.assertEqual(policy, {'videoframework': 'mf'})
        user = json.loads(target.read_text())['current']['general']['user']
        self.assertTrue(user['videohardwareacceleration'])

    def test_explicit_hwa_true_preserves_unselected_framework(self):
        target = self.output / 'config.json'
        target.write_text(json.dumps({'current': {'general': {'user': {
            'videoframework': 'custom', 'videohardwareacceleration': False}}}}))
        policy = module.configure_engine_file(target, self.output, 'current', video_hardware_acceleration=True)
        self.assertEqual(policy, {'videohardwareacceleration': True})
        user = json.loads(target.read_text())['current']['general']['user']
        self.assertEqual(user['videoframework'], 'custom')
        self.assertTrue(user['videohardwareacceleration'])


class WindowControlPreparation(unittest.TestCase):
    def test_pinned_helper_requires_verified_engine_and_preserves_source(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root); out = root / 'out'; out.mkdir()
            helper = root / 'helper.exe'; helper.write_bytes(b'fixture helper')
            engine = root / 'engine.exe'; engine.write_bytes(b'fixture original engine')
            source_hash = hashlib.sha256(engine.read_bytes()).hexdigest()
            helper_hash = hashlib.sha256(helper.read_bytes()).hexdigest()
            with patch.object(module, 'WINDOW_CONTROL_SHA256', helper_hash), patch.object(module, 'WINDOW_CONTROL_ENGINE_SHA256', source_hash):
                result = module.prepare_window_control(helper, engine, out)
                self.assertEqual(result['sha256'], helper_hash)
                self.assertEqual((out / 'window-playback-control.exe').read_bytes(), helper.read_bytes())
                self.assertEqual(hashlib.sha256(engine.read_bytes()).hexdigest(), source_hash)
                engine.write_bytes(b'different engine')
                with self.assertRaisesRegex(ValueError, 'only been verified'):
                    module.prepare_window_control(helper, engine, out)
                self.assertEqual((out / 'window-playback-control.exe').read_bytes(), b'fixture helper')

    def test_helper_hash_mismatch_does_not_replace_previous_helper(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root); out = root / 'out'; out.mkdir()
            (out / 'window-playback-control.exe').write_bytes(b'previous')
            helper = root / 'helper.exe'; helper.write_bytes(b'tampered')
            with self.assertRaisesRegex(ValueError, 'helper hash mismatch'):
                module.prepare_window_control(helper, root / 'not-read.exe', out)
            self.assertEqual((out / 'window-playback-control.exe').read_bytes(), b'previous')


if __name__ == '__main__':
    unittest.main()
