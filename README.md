> Wine playback branch based on v1.1.1, retaining its management, download and menu bar UI. See the [setup, build and limitations guide (Chinese)](docs/wine-playback.zh-CN.md).


# Livewallpaper for macOS

**Languages:** English | [简体中文](README.zh-Hans.md)

![LiveWallpaper](./Assets.xcassets/LiveWallpaperIcon.appiconset/icon_512x512.png)

LiveWallpaper is an open-source live wallpaper app for macOS 14+.

## Purpose

The goal is simple: make video wallpapers feel practical on macOS. This branch combines native local video playback with original Wallpaper Engine playback through Wine, while retaining the v1.1.1 management and download UI.

This project is based on the release source of [thusvill/LiveWallpaperMacOS](https://github.com/thusvill/LiveWallpaperMacOS), then adjusted for the current SwiftUI app, status bar workflow, and Workshop import features.

LiveWallpaper is not affiliated with, endorsed by, or sponsored by Wallpaper Engine Team, Valve, Steam, or any Steam Workshop creator.

## Workshop import

Workshop downloads retain the complete project through a `.weproject` library entry. Scene / Web / Video projects route to the original engine; standalone `.mp4` / `.mov` files use the native player. Scene playback has been tested on hardware; Web / Video project coverage remains limited. Application wallpapers are not launched automatically.

Workshop downloads require Python, SteamCMD and your own Steam login. These download dependencies are not all bundled.

Use Workshop content only through your own Steam account and only when you have the right to access it. LiveWallpaper does not include, host, or redistribute Workshop content; users are responsible for complying with Steam's terms and each Workshop item's license or creator permissions.

## Install v2.0.0

Download `Livewallpaper-for-macOS-v2.0.0.zip` from the [v2.0.0 release](https://github.com/Cold-T/LiveWallpaper-for-macOS/releases/tag/v2.0.0), extract it, and move `Livewallpaper for macOS.app` into Applications. Requires Apple Silicon and macOS 14.6 or later. The app is ad-hoc signed and is not notarized by Apple.

The public package contains the frontend, native helper, playback adapters and selected Wine media patch sources. It does not include the commercial Wallpaper Engine, a complete Wine/DXMT runtime or wallpapers. Standalone MP4/MOV files work directly. Scene/Web projects require your own engine installation and a prepared external compatibility runtime, selected in Settings. See the [runtime guide](docs/wine-playback.zh-CN.md).

Workshop downloads additionally require Python, SteamCMD and your own Steam login. Earlier local personal bundles are separate builds and are not this public download.

## Build from source

Requires macOS, Python 3, Xcode and Apple Command Line Tools with the Swift compiler, and the yaml-cpp submodule. From this checkout:

```sh
git submodule update --init --recursive
python3 tools/build_wine_preview.py
```

This builds the frontend preview without downloading or bundling the Windows engine. See the [integration guide](docs/wine-playback.zh-CN.md) for runtime preparation and personal packaging.

## Usage

Select a wallpaper folder in Settings, then click a thumbnail to play it on the selected display. Use the menu bar to stop, switch wallpapers or reopen the main window. Folder and file names may contain spaces.

## Gallery

> ![Application](./asset/application.png)

> ## This is a static image, currently LiveWallpaper doesn't support videos on the lock screen.
> ![lockscreen](./asset/lockscreen.png)

> ![settings](./asset/settings.png)

> https://github.com/user-attachments/assets/36fb169e-b7cc-4489-9459-dab07c8dd2c6




> # Performance
> ![p1](./asset/preformance1.png)
> ![p2](./asset/preformance2.png)
> ![p3](./asset/preformance3.png)





## License

LiveWallpaper is distributed under the GNU General Public License version 3 or later. See [LICENSE](LICENSE), [NOTICE](NOTICE), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), and [CONTRIBUTORS.md](CONTRIBUTORS.md).

## Credits

[Wallpaper Engine](https://icons8.com/icon/jQspry5Tmnu5/wallpaper-engine) icon by [Icons8](https://icons8.com).
