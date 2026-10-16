#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
out="$task_root/build/media-bridge"
app="$out/LiveWallpaper Media Helper.app"
mkdir -p "$out" "$app/Contents/MacOS"
sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
/Library/Developer/CommandLineTools/usr/bin/clang -fobjc-arc -fblocks -Wall -Wextra \
  -isysroot "$sdk" -mmacosx-version-min=14.0 \
  "$task_root/playback/media_bridge/native/lwmedia-helper.m" \
  -framework Foundation -framework AppKit -framework Carbon \
  -Wl,-sectcreate,__TEXT,__info_plist,"$task_root/playback/media_bridge/native/Info.plist" \
  -o "$out/lwmedia-helper"
/usr/bin/codesign --force --sign - --identifier local.livewallpaper.media-helper "$out/lwmedia-helper"
cp -X "$out/lwmedia-helper" "$app/Contents/MacOS/lwmedia-helper"
cp -X "$task_root/playback/media_bridge/native/Info.plist" "$app/Contents/Info.plist"
# File Provider adds FinderInfo when the app directory is created in Documents.
# Strip only this generated bundle's non-code Finder metadata before signing.
/usr/bin/xattr -d com.apple.FinderInfo "$app" 2>/dev/null || true
/usr/bin/codesign --force --sign - --identifier local.livewallpaper.media-helper "$app"
/opt/homebrew/bin/python3.13 - "$app" "$out" <<'PY'
from pathlib import Path
import json
import subprocess
import sys
import tempfile
import zipfile
app, out = map(Path, sys.argv[1:])
archive = out / "LiveWallpaper-Media-Helper.zip"
# zipfile records content/mode, not File Provider's regenerated FinderInfo.
with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as z:
    for path in sorted(app.rglob("*")):
        if path.is_file():
            z.write(path, path.relative_to(app.parent))
staging = Path(tempfile.mkdtemp(prefix="LiveWallpaper-MediaBridge-", dir="/private/tmp"))
with zipfile.ZipFile(archive) as z:
    z.extractall(staging)
staged_app = staging / app.name
(staged_app / "Contents/MacOS/lwmedia-helper").chmod(0o755)
subprocess.run(["/usr/bin/codesign", "--verify", "--strict", "--verbose=2", str(staged_app)], check=True)
(out / "native-build.json").write_text(json.dumps({
    "archive": str(archive), "verifiedApp": str(staged_app),
    "identity": "local.livewallpaper.media-helper", "signing": "ad-hoc",
    "appleEventsSent": 0, "permissionPrompted": False,
    "workspaceAppCaveat": "Documents File Provider can re-add FinderInfo; use archive or verified staged app"
}, indent=2) + "\n")
print(staged_app)
PY
echo "$out/lwmedia-helper"
