#!/usr/bin/env python3
"""Build an isolated local preview using direct Apple compiler executables."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/preview"
APP = OUT / "Livewallpaper for macOS.app"
SDK = Path("/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")
BIN = Path("/Library/Developer/CommandLineTools/usr/bin")


def run(args):
    subprocess.run([str(x) for x in args], cwd=ROOT, check=True)


def copy_without_xattrs(source, destination):
    """Preserve executable modes while excluding FileProvider/Finder xattrs."""
    shutil.copyfile(source, destination)
    shutil.copymode(source, destination)
    return destination


def copy_resource_tree(source, destination, ignored):
    """Replace an owned resource tree so deleted/now-excluded files cannot ship."""
    if destination.is_symlink():
        destination.unlink()
    elif destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination, ignore=shutil.ignore_patterns(*ignored))


def build(work):
    for directory in (ROOT / "build", OUT, APP, APP / "Contents", APP / "Contents/MacOS", APP / "Contents/Resources"):
        if directory.is_symlink():
            raise ValueError(f"Build output directory must not be a symlink: {directory}")
    OUT.mkdir(parents=True, exist_ok=True)
    # FileProvider can update cached object metadata during Swift's input check.
    # Keep compiler inputs and caches on the ordinary temporary filesystem.
    objects = work / "objects"
    objects.mkdir(exist_ok=True)
    macos = APP / "Contents/MacOS"
    resources = APP / "Contents/Resources"
    macos.mkdir(parents=True, exist_ok=True)
    resources.mkdir(exist_ok=True)
    common = ["-isysroot", SDK, "-mmacosx-version-min=14.6", "-std=c++17", "-isystem", SDK / "usr/include/c++/v1", "-I", ROOT / "vendor/yaml-cpp/include", "-fmodules", "-fmodules-cache-path=" + str(work / "modules")]
    sources = list((ROOT / "vendor/yaml-cpp/src").glob("*.cpp")) + [ROOT / f for f in ["LiveWallpaper.mm", "DisplayObjc.mm", "SaveSystem.mm", "playback/bundle/BundledRuntime.mm", "playback/setup/FirstRunSetup.mm"]]
    def compile_one(source):
        obj = objects / (source.name + ".o")
        if obj.exists() and source.suffix == ".cpp" and obj.stat().st_mtime >= source.stat().st_mtime: return obj
        flags = ["-fobjc-arc"] if source.suffix == ".mm" else []
        run([BIN / "clang++", *common, *flags, "-c", source, "-o", obj])
        return obj
    with ThreadPoolExecutor(max_workers=4) as pool:
        objs = list(pool.map(compile_one, sources))
    frameworks = ["AppKit", "AVFoundation", "QuartzCore", "CoreGraphics", "IOKit", "ServiceManagement", "UniformTypeIdentifiers"]
    link = [option for framework in frameworks for option in ["-framework", framework]]
    run([BIN / "swiftc", "-sdk", SDK, "-target", "arm64-apple-macos14.6", "-swift-version", "6",
         "-default-isolation", "MainActor",
         "-external-plugin-path", "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins#/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/bin/swift-plugin-server", "-enable-upcoming-feature", "NonisolatedNonsendingByDefault",
          "-I", ROOT / "vendor/yaml-cpp/include",
         "-module-cache-path", work / "swift-modules", "-import-objc-header", ROOT / "LiveWallpaper-Bridging-Header.h",
         ROOT / "LiveWallpaperApp.swift", ROOT / "ContentView.swift", ROOT / "FirstRunSetupView.swift", *objs, *link, "-lc++", "-o", macos / "LiveWallpaper"])
    run([BIN / "clang++", *common, "-fobjc-arc", ROOT / "wallpaperdaemon/daemon.mm", *link, "-o", macos / "wallpaperdaemon"])
    for directory in ["tools", "playback", "asset", "en.lproj", "zh-Hans.lproj"]:
        ignored = ("__pycache__", "media_bridge", "diagnostics") if directory == "playback" else ("__pycache__",)
        copy_resource_tree(ROOT / directory, resources / directory, ignored)
    run([BIN / "clang", "-arch", "x86_64", "-arch", "arm64", "-isysroot", SDK,
         "-mmacosx-version-min=14.6", "-dynamiclib", "-O2", "-fblocks",
         ROOT / "playback/wine_volume.c", ROOT / "playback/wine_app_identity.m", "-fobjc-arc",
         "-framework", "AppKit", "-framework", "AudioUnit", "-framework", "AudioToolbox",
         "-o", resources / "playback/bin/wine_volume.dylib"])
    # Source staging may lose executable bits; child download scripts are
    # invoked directly by the Workshop coordinator.
    for script in (resources / "tools").glob("*.sh"):
        script.chmod(script.stat().st_mode | 0o111)
    for document in ["LICENSE", "NOTICE", "THIRD_PARTY_NOTICES.md", "CONTRIBUTORS.md"]:
        shutil.copy2(ROOT / document, resources / document)
    shutil.copy2(ROOT / "vendor/yaml-cpp/LICENSE", resources / "YAML-CPP-LICENSE")
    # Prefer a compiled asset catalog if available; icon remains usable without it.
    catalog = ROOT.parent / "LiveWallpaper-for-macOS/build/local/LiveWallpaper.app/Contents/Resources/Assets.car"
    if not catalog.exists(): catalog = Path("/Applications/LiveWallpaper.app/Contents/Resources/Assets.car")
    if catalog.exists(): shutil.copy2(catalog, resources / "Assets.car")
    else:
        for image_set in (ROOT / "Assets.xcassets").glob("*.imageset"):
            for image in image_set.iterdir():
                if image.suffix in {".png", ".svg"}:
                    shutil.copy2(image, resources / (image_set.stem + image.suffix))
    for icon in (ROOT / "asset").glob("*.icns"): shutil.copy2(icon, resources / icon.name)
    installed_icon = Path("/Applications/LiveWallpaper.app/Contents/Resources/LiveWallpaperIcon.icns")
    if installed_icon.exists(): shutil.copy2(installed_icon, resources / installed_icon.name)
    (APP / "Contents/Info.plist").write_bytes(plistlib.dumps({
        "CFBundleExecutable": "LiveWallpaper", "CFBundleIdentifier": "uk.coldt.LiveWallpaper.WinePreview",
        "CFBundleName": "Livewallpaper for macOS", "CFBundleDisplayName": "Livewallpaper for macOS",
        "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "2.0.1", "CFBundleVersion": "206",
        "LSUIElement": True, "NSHighResolutionCapable": True, "NSPrincipalClass": "NSApplication",
        "CFBundleIconFile": "LiveWallpaperIcon", "LSMinimumSystemVersion": "14.6",
    }))
    # File-provider folders may restore FinderInfo immediately. Sign and verify
    # outside those folders, then save an archive that carries no extended attrs.
    with tempfile.TemporaryDirectory(prefix="lw-preview-sign-", dir="/private/tmp") as temporary:
        stage = Path(temporary) / APP.name
        shutil.copytree(APP, stage, copy_function=copy_without_xattrs)
        run(["/usr/bin/xattr", "-cr", stage])
        run(["/usr/bin/codesign", "--force", "--deep", "--sign", "-", stage])
        run(["/usr/bin/codesign", "--verify", "--deep", "--strict", stage])
        distribution = ROOT / "dist"
        distribution.mkdir(exist_ok=True)
        shutil.make_archive(str(distribution / "Livewallpaper-for-macOS-v2.0.1"), "zip", temporary)
        shutil.copytree(stage, APP, dirs_exist_ok=True, copy_function=copy_without_xattrs)
    print(APP)


def main():
    with tempfile.TemporaryDirectory(prefix="lw-preview-compile-", dir="/private/tmp") as temporary:
        build(Path(temporary))


if __name__ == "__main__": main()
