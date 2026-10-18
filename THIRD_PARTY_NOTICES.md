# Third Party Notices

## Upstream Project

LiveWallpaper is based on release source from [thusvill/LiveWallpaperMacOS](https://github.com/thusvill/LiveWallpaperMacOS), licensed under GPL-3.0-or-later.

## Bundled Libraries

`vendor/yaml-cpp` is licensed under the MIT License. See [vendor/yaml-cpp/LICENSE](vendor/yaml-cpp/LICENSE).

The vendored yaml-cpp test tree includes GoogleTest 1.13.0 under a BSD-style license. See [vendor/yaml-cpp/test/googletest-1.13.0/LICENSE](vendor/yaml-cpp/test/googletest-1.13.0/LICENSE).

## Icons

The app icon uses the Icons8 Wallpaper Engine icon with attribution:
[Wallpaper Engine icon by Icons8](https://icons8.com/icon/jQspry5Tmnu5/wallpaper-engine).

## Steam and Wallpaper Engine

Steam, Wallpaper Engine, and Steam Workshop names are used only to describe interoperability and content source. LiveWallpaper is not affiliated with, endorsed by, or sponsored by Wallpaper Engine Team, Valve, Steam, or any Steam Workshop creator.

## Online setup and adapter overlay

The public online installer downloads pinned Sikarugir Wine, Template and Gcenx archives directly from their publishers on the user's machine. Those vendor archives, frameworks, libraries and fonts are not included in the installer overlay. Exact URLs, archive SHA-256 hashes and installed-file hashes are recorded in `SetupRuntime.json`.

The redistributed overlay contains DXMT's five selected graphics files, three modified Wine media modules and the project's desktop/control helpers. DXMT commit `186a2327f1ec76376f6bc1ef64636f08b0728567` is copyright Feifan He for CodeWeavers, LGPL-2.1-or-later; its fixed NVIDIA NVAPI and mingw-directx-headers submodules retain their own licenses. Modified Wine media modules derive from Wine11 commit `db11d0fe6a169c457e23d007e20404643d067aa8`, LGPL-2.1-or-later. Project-owned helpers are covered by this repository's GPL-3.0-or-later license.

The app carries adapter notices and full license texts. The [runtime source archive](https://github.com/Cold-T/LiveWallpaper-for-macOS/releases/tag/runtime-sources-v2.0.0) provides `Runtime-Adapter-Sources.tar.gz`: exact DXMT and submodule source archives, Wine upstream build input, complete patched media source, patches, build scripts and tests. The selected media receipt is `playback/patches/source-pool-package/release-candidate-schema1.json`. This source package does not claim to cover all publisher-supplied vendor binaries.

Vendor origins: [Sikarugir Wine revision1](https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineSikarugir11.0_1.tar.xz), [Template1.0.21](https://github.com/Sikarugir-App/Template/releases/download/v1.0/Template-1.0.21.tar.xz), [Gcenx native-library archive](https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.0_1/wine-stable-11.0_1-osx64.tar.xz).

## User-supplied Wallpaper Engine

Users import their own Wallpaper Engine 2.8.42 installation. Those executable and resource files retain their original authors’ licenses. The LiveWallpaper GPL license applies to this project's own code.
