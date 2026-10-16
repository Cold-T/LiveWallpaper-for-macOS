"""Offline integration tests for the Workshop collection coordinator."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class WorkshopCoordinatorTests(unittest.TestCase):
    def test_collection_continues_after_failed_download_and_rejects_application_video(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            tools = root / "tools"
            tools.mkdir()
            for name in ["download_import_play_workshop_item.sh", "import_engine_project.py"]:
                shutil.copyfile(ROOT / "tools" / name, tools / name)
            downloader = tools / "download_wallpaper_engine_item.sh"
            downloader.write_text('#!/bin/bash\n[[ "$1" != 456 ]]\n')
            downloader.chmod(0o755)
            fake_bin = root / "bin"
            fake_bin.mkdir()
            python = fake_bin / "python3"
            python.write_text(
                '#!/bin/bash\n'
                'if [[ "$#" == 2 && "$1" == - ]]; then\n'
                "  printf '123\\n456\\n789\\n888\\n'\n"
                'else\n'
                f'  exec "{sys.executable}" "$@"\n'
                'fi\n'
            )
            python.chmod(0o755)
            workshop = root / "workshop"
            content = workshop / "steamapps/workshop/content/431960"
            for item, kind, entry in [("123", "web", "index.html"), ("456", "video", "stale.mp4"), ("789", "application", "app.exe")]:
                source = content / item
                source.mkdir(parents=True)
                # UTF-8 BOM is valid in published project metadata.
                (source / "project.json").write_text(json.dumps({"type": kind, "file": entry}), encoding="utf-8-sig")
                (source / entry).write_text("fixture")
                (source / "embedded.mp4").write_text("fixture")
            malformed = content / "888"
            malformed.mkdir()
            (malformed / "project.json").write_text("[]")
            (malformed / "embedded.mp4").write_text("fixture")
            library = root / "library"
            result = subprocess.run(
                ["/bin/bash", str(tools / "download_import_play_workshop_item.sh"), "321"],
                env={**os.environ, "PATH": str(fake_bin) + ":" + os.environ.get("PATH", ""),
                     "LIVEWALLPAPER_STEAM_WORKSHOP_DIR": str(workshop),
                     "LIVEWALLPAPER_IMPORT_DIR": str(library),
                     "LIVEWALLPAPER_SKIP_PLAY": "1"},
                text=True, capture_output=True, timeout=10,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("Imported collection: 1 wallpapers", result.stdout)
            self.assertIn("Skipped items: 3", result.stdout)
            self.assertEqual([path.name for path in library.iterdir()], ["123.weproject"])
            self.assertIn("Unsupported Workshop project type: application", result.stderr)
            self.assertTrue((content / "456/stale.mp4").exists())


if __name__ == "__main__":
    unittest.main()
