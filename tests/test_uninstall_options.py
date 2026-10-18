import subprocess
import unittest
from pathlib import Path

SCRIPT=Path(__file__).resolve().parents[1]/'tools/uninstall-livewallpaper.command'
class UninstallOptionTests(unittest.TestCase):
    def run_script(self,*args):
        return subprocess.run(['/bin/bash',str(SCRIPT),*args],text=True,capture_output=True)
    def test_preview_defaults_to_keep(self):
        r=self.run_script('--dry-run');self.assertEqual(r.returncode,0);self.assertIn('Downloaded wallpapers will be kept:',r.stdout)
    def test_removal_is_explicit_and_preview_always_wins(self):
        for args in [('--dry-run','--yes','--remove-wallpapers'),('--yes','--remove-wallpapers','--dry-run')]:
            r=self.run_script(*args);self.assertEqual(r.returncode,0);self.assertIn('Downloaded Wallpaper Engine wallpapers will move to Trash:',r.stdout);self.assertIn('Dry run:',r.stdout)
    def test_conflicting_policies_fail_before_cleanup(self):
        r=self.run_script('--remove-wallpapers','--keep-wallpapers');self.assertEqual(r.returncode,2);self.assertIn('Choose either',r.stderr)
