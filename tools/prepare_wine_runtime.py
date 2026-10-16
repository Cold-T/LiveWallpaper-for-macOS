#!/usr/bin/env python3
"""Assemble a local runtime from the previously verified free Wine + DXMT build.
Does not download or redistribute Wallpaper Engine. Uses APFS copies so changes
in the runtime never change the supplied installation or previous experiment.
"""
import argparse
import getpass
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile


WINDOW_CONTROL_SHA256 = "f2dfa881f4c61bcf01a3e357f47dadbc3caa9a24f59390a6e48ac61cbbef1ffe"
WINDOW_CONTROL_ENGINE_SHA256 = "40e2ce021e9352324fadb3b8f72b8ba2a7ee95b71cc571d5b9f84be75cd993b0"

def prepare_window_control(source, engine, output):
    """Install the pinned helper only for its statically verified original engine."""
    source, engine, output = Path(source), Path(engine), Path(output).resolve()
    data = source.read_bytes()
    if hashlib.sha256(data).hexdigest() != WINDOW_CONTROL_SHA256:
        raise ValueError("Window control helper hash mismatch")
    if hashlib.sha256(engine.read_bytes()).hexdigest() != WINDOW_CONTROL_ENGINE_SHA256:
        raise ValueError("Window control private message protocol has only been verified for engine 2.8.42")
    copy_owned_file(source, output / "window-playback-control.exe", output)
    return {"sha256": WINDOW_CONTROL_SHA256, "engine_sha256": WINDOW_CONTROL_ENGINE_SHA256,
            "protocol": "scene DX11 child WM_USER+11, exact title + pinned Windows PID",
            "timeout_ms": 2000, "identity_bootstrap": "read-only identify after ready",
            "acknowledgement": "message delivery; visual/time pause needs runtime verification"}


def clone(source, destination):
    subprocess.run(["/bin/cp", "-cR", str(source), str(destination)], check=True)


def prepare_vulkan(frameworks, output):
    """Copy a matching free loader/driver and keep its ICD runtime-relative."""
    frameworks, output = Path(frameworks).resolve(), Path(output).resolve()
    loader = (frameworks / "libvulkan.1.dylib").resolve(strict=True)
    driver = (frameworks / "libMoltenVK.dylib").resolve(strict=True)
    source_icd = frameworks.parent / "Resources/vulkan/icd.d/MoltenVK_icd.json"
    icd = json.loads(source_icd.read_text())
    icd["ICD"]["library_path"] = "../../lib/libMoltenVK.dylib"
    libraries = output / "lib"
    if not libraries.is_dir() or libraries.is_symlink():
        raise ValueError("Vulkan libraries need an application-owned runtime/lib directory")
    for source, name in ((loader, "libvulkan.1.dylib"), (driver, "libMoltenVK.dylib")):
        destination = libraries / name
        if destination.is_symlink():
            destination.unlink()
        shutil.copy2(source, destination)
    destination_icd = output / "vulkan/icd.d/MoltenVK_icd.json"
    destination_icd.parent.mkdir(parents=True, exist_ok=True)
    destination_icd.write_text(json.dumps(icd, indent=2))
    return {"source_frameworks": str(frameworks), "source_icd": str(source_icd),
            "sha256": {"lib/" + name: hashlib.sha256((libraries / name).read_bytes()).hexdigest()
                       for name in ("libvulkan.1.dylib", "libMoltenVK.dylib")}}


def unify_gstreamer_vulkan(output):
    """GStreamer and Wine must load the same Mach-O image, not duplicate classes."""
    output = Path(output).resolve()
    canonical = output / "lib/libMoltenVK.dylib"
    framework_driver = output / "Frameworks/GStreamer.framework/Versions/1.0/lib/libMoltenVK.dylib"
    if not canonical.is_file() or canonical.is_symlink():
        raise ValueError("Missing private canonical MoltenVK driver")
    if not framework_driver.parent.resolve().is_relative_to(output):
        raise ValueError("GStreamer library directory escapes the runtime")
    if not framework_driver.exists() and not framework_driver.is_symlink():
        raise ValueError("Missing GStreamer MoltenVK library")
    original_hash = hashlib.sha256(framework_driver.read_bytes()).hexdigest()
    framework_driver.unlink()
    framework_driver.symlink_to(os.path.relpath(canonical, framework_driver.parent))
    return {"gstreamer_original_sha256": original_hash,
            "gstreamer_library_link": str(framework_driver.relative_to(output)),
            "canonical_library": str(canonical.relative_to(output))}


def prepare_unix_gstreamer(source, expected_sha256, output):
    """Explicit experimental override; never follow an output link into source."""
    source, output = Path(source).resolve(strict=True), Path(output).resolve()
    data = source.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if not expected_sha256 or digest != expected_sha256.lower():
        raise ValueError("Wine GStreamer candidate SHA256 does not match")
    if len(data) < 32 or data[:4] != b"\xcf\xfa\xed\xfe" or struct.unpack_from("<I", data, 4)[0] != 0x01000007 or struct.unpack_from("<I", data, 12)[0] not in (6, 8):
        raise ValueError("Wine GStreamer candidate must be an x86_64 Mach-O module")
    destination = output / "wine/lib/wine/x86_64-unix/winegstreamer.so"
    if not destination.parent.resolve().is_relative_to(output):
        raise ValueError("Wine Unix module directory escapes the prepared runtime")
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=destination.parent, prefix=".winegstreamer-", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(data)
        temporary.chmod(0o644)
        temporary.replace(destination)
    finally:
        if temporary and temporary.exists():
            temporary.unlink()
    return {"source": str(source), "sha256": digest, "experimental": True,
            "note": "Requires matching Wine ABI and visual verification; explicit operator selection."}



def prepare_media_pe(source, expected_sha256, output, name):
    """Install a verified AMD64 media DLL into the newly owned runtime only."""
    if name not in {"winegstreamer.dll", "mfmediaengine.dll"}:
        raise ValueError("Unexpected media module name")
    source, output = Path(source).resolve(strict=True), Path(output).resolve()
    data = source.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if not expected_sha256 or digest != expected_sha256.lower():
        raise ValueError("Media PE candidate SHA256 does not match")
    if len(data) < 64 or data[:2] != b"MZ":
        raise ValueError("Media candidate must be an AMD64 PE32+ DLL")
    offset = struct.unpack_from("<I", data, 60)[0]
    if (offset > len(data) - 26 or data[offset:offset + 4] != b"PE\0\0"
            or struct.unpack_from("<H", data, offset + 4)[0] != 0x8664
            or not struct.unpack_from("<H", data, offset + 22)[0] & 0x2000
            or struct.unpack_from("<H", data, offset + 24)[0] != 0x20b):
        raise ValueError("Media candidate must be an AMD64 PE32+ DLL")
    destination = output / "wine/lib/wine/x86_64-windows" / name
    if not destination.parent.resolve().is_relative_to(output):
        raise ValueError("Media PE directory escapes the prepared runtime")
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=destination.parent, prefix=".media-pe-", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(data)
        temporary.chmod(0o644)
        temporary.replace(destination)
    finally:
        if temporary and temporary.exists():
            temporary.unlink()
    return {"source": str(source), "sha256": digest, "experimental": True}


def validate_output_location(output, sources):
    """Copies must not recurse into an input or remove input on failure."""
    output = Path(output).resolve()
    for source in sources:
        if source is None:
            continue
        source = Path(source).resolve()
        if output.is_relative_to(source) or source.is_relative_to(output):
            raise ValueError(f"Runtime output overlaps an input: {source}")


def copy_owned_file(source, destination, output):
    """Replace a copied link itself, never write through it into the source."""
    source, destination, output = Path(source), Path(destination), Path(output).resolve()
    if not destination.parent.resolve().is_relative_to(output):
        raise ValueError("Component directory escapes the prepared runtime")
    data = source.read_bytes()
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=destination.parent, prefix=".runtime-component-", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(data)
        temporary.chmod(source.stat().st_mode & 0o777)
        temporary.replace(destination)
    finally:
        if temporary and temporary.exists():
            temporary.unlink()


def verify_media_fix_receipt(receipt, selections):
    """A curated hash set couples all three modules; it does not prove ABI itself."""
    receipt = Path(receipt).resolve(strict=True)
    raw = receipt.read_bytes()
    data = json.loads(raw)
    names = {"winegstreamer.dll", "winegstreamer.so", "mfmediaengine.dll"}
    expected = data.get("modules") if isinstance(data, dict) else None
    if not isinstance(data, dict) or data.get("schema") != 1 or not isinstance(expected, dict) or set(expected) != names:
        raise ValueError("Media fix receipt must identify exactly three modules with schema 1")
    for name in names:
        selected, digest = selections.get(name, (None, None))
        target = expected[name]
        if not selected or not digest:
            raise ValueError("Media fix receipt requires all three matching module selections")
        if not isinstance(target, str) or len(target) != 64 or any(c not in "0123456789abcdef" for c in target):
            raise ValueError("Media fix receipt contains an invalid SHA256")
        if digest.lower() != target or hashlib.sha256(Path(selected).read_bytes()).hexdigest() != target:
            raise ValueError(f"Media fix receipt SHA256 mismatch: {name}")
    return {"source": str(receipt), "sha256": hashlib.sha256(raw).hexdigest(), "receipt": data}


def verify_bootstrap_pe(source):
    data = Path(source).read_bytes()
    valid = len(data) >= 64 and data[:2] == b"MZ"
    offset = struct.unpack_from("<I", data, 60)[0] if valid else 0
    if (not valid or offset > len(data) - 26 or data[offset:offset + 4] != b"PE\0\0"
            or struct.unpack_from("<H", data, offset + 4)[0] != 0x8664
            or not struct.unpack_from("<H", data, offset + 22)[0] & 0x2000
            or struct.unpack_from("<H", data, offset + 24)[0] != 0x20b):
        raise ValueError(f"Player bootstrap needs an AMD64 PE32+ DLL: {source}")
    return hashlib.sha256(data).hexdigest()


def prepare_player_bundle(output):
    """Use one canonical Wine core; copied ntdll breaks @rpath driver identity."""
    output = Path(output).resolve()
    source = output / "wine/lib/wine/x86_64-unix"
    for name in ("wine", "ntdll.so"):
        path = source / name
        if not path.resolve().is_relative_to(output):
            raise ValueError("Canonical Wine core must stay inside the prepared runtime")
        data = path.read_bytes()
        if (len(data) < 32 or data[:4] != b"\xcf\xfa\xed\xfe"
                or struct.unpack_from("<I", data, 4)[0] != 0x01000007
                or struct.unpack_from("<I", data, 12)[0] != (2 if name == "wine" else 6)):
            raise ValueError(f"Player bundle needs the x86_64 native {name}")
    bootstrap = output / "wine/lib/wine/x86_64-windows"
    bootstrap_hashes = {name: verify_bootstrap_pe(bootstrap / name)
                        for name in ("ntdll.dll", "apisetschema.dll")}
    share = output / "wine/share/wine"
    for name in ("wine.inf", "nls/locale.nls", "nls/l_intl.nls", "nls/normnfc.nls"):
        if not (share / name).is_file():
            raise ValueError(f"Player bundle needs canonical Wine data: {share / name}")
    app = output / "WinePlayer.app/Contents"
    (app / "MacOS").mkdir(parents=True)
    copy_owned_file(source / "wine", app / "MacOS/wine", output)
    link = os.path.relpath(source / "ntdll.so", app / "MacOS")
    (app / "MacOS/ntdll.so").symlink_to(link)
    # Both win32u.so and winemac.so import @rpath/ntdll.so with
    # LC_RPATH=@loader_path/. Loading a physical app-local copy first makes
    # those imports resolve a second core image with independent global state.
    # The symlink makes loader init_paths, GUI drivers, PE bootstrap/data and
    # child process loaders all use the original same-runtime canonical core.
    (app / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleExecutable": "wine", "CFBundleIdentifier": "uk.coldt.LiveWallpaper.WinePlayer",
        "CFBundleName": "LiveWallpaperWinePlayer", "CFBundleDisplayName": "Wallpaper Engine Player",
        "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "LSUIElement": True,
        "NSHighResolutionCapable": True,
    }))
    subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-",
                    "--preserve-metadata=entitlements,flags", str(app.parent)], check=True)
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", str(app.parent)], check=True)
    return {"loader_source_sha256": hashlib.sha256((source / "wine").read_bytes()).hexdigest(),
            "ntdll_sha256": hashlib.sha256((source / "ntdll.so").read_bytes()).hexdigest(),
            "loader_sha256": hashlib.sha256((app / "MacOS/wine").read_bytes()).hexdigest(),
            "bootstrap_pe_sha256": bootstrap_hashes,
            "bootstrap_architecture": "x86_64; product renderer is 64-bit",
            "canonical_ntdll_link": link, "canonical_ntdll": str((source / "ntdll.so").resolve()),
            "wine_data_directory": str(share), "single_core_layout": True,
            "signature": "ad-hoc deep verified",
            "strict_signature": {"supported": False,
                                 "reason": "Same-runtime external ntdll code link is rejected by codesign --strict; regular/deep validation succeeds"}}


def configure_engine_file(path, output, username, media_fix=False, video_hardware_acceleration=None):
    """Apply policy to the owned copy; keep source links and quality intact."""
    path, output = Path(path), Path(output).resolve()
    if not path.parent.resolve().is_relative_to(output):
        raise ValueError("Engine config directory escapes the prepared runtime")
    config = json.loads(path.read_text()) if path.exists() else {}
    if not isinstance(config, dict):
        raise ValueError("Engine config must be a JSON object")
    config.pop("?installdirectory", None)
    profile = config.setdefault(username, {})
    if not isinstance(profile, dict):
        raise ValueError("Current engine profile must be an object")
    general = profile.setdefault("general", {})
    if not isinstance(general, dict):
        raise ValueError("Engine general settings must be an object")
    user = general.setdefault("user", {})
    if not isinstance(user, dict):
        raise ValueError("Engine user settings must be an object")
    user.update(mediaintegration=False, uihardwareacceleration=False,
                cefcommandline="--disable-gpu --disable-gpu-compositing", hasshownwelcomedialog=True)
    if video_hardware_acceleration is not None and not isinstance(video_hardware_acceleration, bool):
        raise ValueError("Video hardware acceleration must be an explicit boolean")
    backend = {"videoframework": "mf"} if media_fix else {}
    if video_hardware_acceleration is not None:
        backend["videohardwareacceleration"] = video_hardware_acceleration
    backend = backend or None
    if backend:
        for item in config.values():
            if isinstance(item, dict) and isinstance(item.get("general"), dict):
                settings = item["general"].setdefault("user", {})
                if not isinstance(settings, dict):
                    raise ValueError("Engine user settings must be an object")
                settings.update(backend)
    # An input config may have been a symlink: atomically replace that copied
    # directory entry, never truncate the original installation's config.
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".engine-config-", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(json.dumps(config, indent=2).encode())
        temporary.chmod(0o644)
        temporary.replace(path)
    finally:
        if temporary and temporary.exists():
            temporary.unlink()
    return backend


def prepare(engine, wine, fallback, output, gstreamer, dxmt=None, vulkan_frameworks=None,
            wine_gstreamer_unix=None, wine_gstreamer_sha256=None,
            wine_gstreamer_pe=None, wine_gstreamer_pe_sha256=None,
            media_engine_pe=None, media_engine_pe_sha256=None, media_fix_receipt=None, bridge_source=None, video_hardware_acceleration=None, window_control=None):
    engine, wine, fallback, output = [Path(p).resolve() for p in (engine, wine, fallback, output)]
    gstreamer = Path(gstreamer).resolve()
    dxmt = Path(dxmt).resolve() if dxmt else None
    vulkan_frameworks = Path(vulkan_frameworks).resolve() if vulkan_frameworks else gstreamer.parent
    if bool(wine_gstreamer_unix) != bool(wine_gstreamer_sha256):
        raise ValueError("A Wine GStreamer candidate needs both a module path and its expected SHA256")
    if bool(wine_gstreamer_pe) != bool(wine_gstreamer_pe_sha256):
        raise ValueError("A Wine GStreamer PE candidate needs its expected SHA256")
    if wine_gstreamer_pe and not wine_gstreamer_unix:
        raise ValueError("A Wine GStreamer PE candidate requires its matching Unix module")
    if bool(media_engine_pe) != bool(media_engine_pe_sha256):
        raise ValueError("A MediaEngine PE candidate needs its expected SHA256")
    fix_receipt = verify_media_fix_receipt(media_fix_receipt, {
        "winegstreamer.dll": (wine_gstreamer_pe, wine_gstreamer_pe_sha256),
        "winegstreamer.so": (wine_gstreamer_unix, wine_gstreamer_sha256),
        "mfmediaengine.dll": (media_engine_pe, media_engine_pe_sha256),
    }) if media_fix_receipt else None
    bridge_source = Path(bridge_source).resolve(strict=True) if bridge_source else Path(__file__).resolve().parents[1] / "playback/desktop_window_bridge.m"
    window_control = Path(window_control).resolve(strict=True) if window_control else Path(__file__).resolve().parents[1] / "playback/bin/window-playback-control.exe"
    validate_output_location(output, (engine, wine, fallback, gstreamer, dxmt, vulkan_frameworks,
                                      wine_gstreamer_unix, wine_gstreamer_pe, media_engine_pe,
                                      media_fix_receipt, bridge_source, window_control))
    for file in (engine / "wallpaper64.exe", wine / "bin/wine", wine / "bin/wineserver",
                 wine / "lib/wine/x86_64-unix/wine", wine / "lib/wine/x86_64-unix/ntdll.so",
                 wine / "lib/wine/x86_64-windows/winemetal.dll", fallback,
                 engine / "assets/fonts/RobotoMono-Regular.ttf",
                 vulkan_frameworks / "libvulkan.1.dylib", vulkan_frameworks / "libMoltenVK.dylib",
                 vulkan_frameworks.parent / "Resources/vulkan/icd.d/MoltenVK_icd.json",
                 gstreamer / "Versions/1.0/lib/gstreamer-1.0/libgstlibav.dylib",
                 gstreamer / "Versions/1.0/libexec/gstreamer-1.0/gst-plugin-scanner"):
        if not file.exists():
            raise ValueError(f"Required runtime component not found: {file}")
    if output.exists():
        raise ValueError("Choose a new output directory; existing runtime is never overwritten")
    output.mkdir(parents=True)
    try:
        clone(engine, output / "engine")
        clone(wine, output / "wine")
        clone(fallback, output / "lib")
        vulkan = prepare_vulkan(vulkan_frameworks, output)
        (output / "Frameworks").mkdir()
        clone(gstreamer, output / "Frameworks/GStreamer.framework")
        vulkan["shared_driver"] = unify_gstreamer_vulkan(output)
        gst_override = prepare_unix_gstreamer(wine_gstreamer_unix, wine_gstreamer_sha256, output) if wine_gstreamer_unix else None
        gst_pe_override = prepare_media_pe(wine_gstreamer_pe, wine_gstreamer_pe_sha256, output,
                                           "winegstreamer.dll") if wine_gstreamer_pe else None
        engine_pe_override = prepare_media_pe(media_engine_pe, media_engine_pe_sha256, output,
                                              "mfmediaengine.dll") if media_engine_pe else None
        # Always replace a complete matching DXMT set, including the Unix side.
        dxmt_files = ["x86_64-windows/" + name for name in
                      ("d3d11.dll", "dxgi.dll", "d3d10core.dll", "winemetal.dll")]
        dxmt_files.append("x86_64-unix/winemetal.so")
        if dxmt:
            for name in dxmt_files:
                copy_owned_file(dxmt / name, output / "wine/lib/wine" / name, output)
        media_backend = configure_engine_file(output / "engine/config.json", output,
                                              getpass.getuser(), media_fix=bool(fix_receipt),
                                              video_hardware_acceleration=video_hardware_acceleration)
        window_control_metadata = prepare_window_control(window_control, engine / "wallpaper64.exe", output)
        player_bundle = prepare_player_bundle(output)
        compiler = "/Library/Developer/CommandLineTools/usr/bin/clang"
        sdk = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
        source = bridge_source
        subprocess.run([compiler, "-arch", "x86_64", "-isysroot", sdk, "-mmacosx-version-min=14.0",
            "-dynamiclib", "-fobjc-arc", "-fblocks", str(source), "-o", str(output / "desktop_window_bridge.dylib"),
            "-framework", "AppKit", "-framework", "CoreGraphics", "-framework", "QuartzCore"], check=True)
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(output / "desktop_window_bridge.dylib")], check=True)
        subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(output / "desktop_window_bridge.dylib")], check=True)
        digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
        if digest(engine / "wallpaper64.exe") != digest(output / "engine/wallpaper64.exe"):
            raise ValueError("Copied Wallpaper Engine executable differs from the original")
        (output / "runtime.json").write_text(json.dumps({
            "schema": 3, "engine_sha256": digest(engine / "wallpaper64.exe"),
            "source_engine": str(engine), "source_wine": str(wine),
            "wine_version": (wine / "version").read_text().strip() if (wine / "version").exists() else "unspecified",
            "source_gstreamer": str(gstreamer), "source_dxmt": str(dxmt) if dxmt else str(wine),
            "player_bundle": player_bundle,
            "window_control": window_control_metadata,
            "desktop_bridge": {"source": str(source), "source_sha256": digest(source),
                               "sha256": digest(output / "desktop_window_bridge.dylib"),
                               "signature": "ad-hoc strict verified"},
            "launch_environment": {"SikarugirAppWine11": "1", "WINELOADERNOEXEC": "1",
                                   "WINEDLLPATH": str(output / "wine/lib/wine"),
                                   "WINESERVER": str(output / "wine/bin/wineserver")},
            "launch_path_prepend": str(output / "wine/bin"),
            "media_fix_receipt": fix_receipt,
            "component_sha256": {name: digest(output / "wine/lib/wine" / name) for name in dxmt_files},
            "vulkan": vulkan,
            "wine_gstreamer_unix": gst_override,
            "wine_gstreamer_pe": gst_pe_override,
            "media_engine_pe": engine_pe_override,
            "compatibility_policy": {"windows_media_integration": False,
                                     "media_backend": media_backend,
                                     "installed_windows_fonts": "Prefer exact local font filenames; symlink only, never bundled",
                                     "missing_consolas_fallback": "engine/assets/fonts/RobotoMono-Regular.ttf"},
            "note": "Local personal runtime. Original Windows executables unchanged. Not a redistribution package.",
        }, indent=2))
        return output
    except BaseException:
        shutil.rmtree(output)
        raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", required=True)
    parser.add_argument("--wine", required=True, help="Verified Wine directory with DXMT builtin DLLs already installed")
    parser.add_argument("--fallback", required=True, help="Free Gcenx Wine native lib directory")
    parser.add_argument("--gstreamer", required=True, help="Complete x86_64 GStreamer.framework matching Wine's ABI")
    parser.add_argument("--dxmt", help="Optional complete matching DXMT directory with x86_64-windows and x86_64-unix")
    parser.add_argument("--vulkan-frameworks", help="Matching free Vulkan loader/MoltenVK Frameworks directory; defaults to GStreamer's parent")
    parser.add_argument("--wine-gstreamer-unix", help="Explicit experimental x86_64 Unix module built for this Wine ABI")
    parser.add_argument("--wine-gstreamer-sha256", help="Required expected SHA256 for --wine-gstreamer-unix")
    parser.add_argument("--wine-gstreamer-pe", help="Matched experimental GStreamer PE DLL; requires the Unix candidate")
    parser.add_argument("--wine-gstreamer-pe-sha256", help="Required SHA256 for the matched GStreamer PE DLL")
    parser.add_argument("--media-engine-pe", help="Explicit experimental MediaEngine PE DLL")
    parser.add_argument("--media-engine-pe-sha256", help="Required SHA256 for the MediaEngine PE DLL")
    parser.add_argument("--media-fix-receipt", help="Optional reviewed schema-1 hash set coupling all three media modules")
    parser.add_argument("--window-control", help="Optional physical copy of the pinned window control helper")
    parser.add_argument("--bridge-source", help="Optional physical desktop_window_bridge.m path with its adjacent headers")
    parser.add_argument("--video-hardware-acceleration", action=argparse.BooleanOptionalAction, default=None,
                        help="Explicit video HWA selection; absent preserves source config")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        print(prepare(args.engine, args.wine, args.fallback, args.output, args.gstreamer, args.dxmt, args.vulkan_frameworks,
                      args.wine_gstreamer_unix, args.wine_gstreamer_sha256,
                      args.wine_gstreamer_pe, args.wine_gstreamer_pe_sha256,
                      args.media_engine_pe, args.media_engine_pe_sha256, args.media_fix_receipt, args.bridge_source, args.video_hardware_acceleration, args.window_control))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
