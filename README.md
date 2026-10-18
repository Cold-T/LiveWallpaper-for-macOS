> Wine playback branch based on v1.1.1, retaining its management, download and menu bar UI. See the [setup, build and limitations guide (Chinese)](docs/wine-playback.zh-CN.md).


# Livewallpaper for macOS

**Languages:** English | [简体中文](README.zh-Hans.md)

![LiveWallpaper](./Assets.xcassets/LiveWallpaperIcon.appiconset/icon_512x512.png)

LiveWallpaper is an open-source live wallpaper app for Apple Silicon Macs running macOS 14.6+.

## Purpose

The goal is simple: make video wallpapers feel practical on macOS. This branch combines native local video playback with original Wallpaper Engine playback through Wine, while retaining the v1.1.1 management and download UI.

This project is based on the release source of [thusvill/LiveWallpaperMacOS](https://github.com/thusvill/LiveWallpaperMacOS), then adjusted for the current SwiftUI app, status bar workflow, and Workshop import features.

LiveWallpaper is not affiliated with, endorsed by, or sponsored by Wallpaper Engine Team, Valve, Steam, or any Steam Workshop creator.

## Workshop import

Workshop downloads retain the complete project through a `.weproject` library entry. Scene / Web projects route to the original engine; Video projects and standalone `.mp4` / `.mov` files use the v1.1.1 native macOS player. Scene playback has been tested on hardware; Web / Video project coverage remains limited. Application wallpapers are not launched automatically.

Workshop downloads require Python, SteamCMD and your own Steam login. These download dependencies are not all bundled.

Use Workshop content only through your own Steam account and only when you have the right to access it. LiveWallpaper does not include, host, or redistribute Workshop content; users are responsible for complying with Steam's terms and each Workshop item's license or creator permissions.

## Install v2.0.0

Requirements: **Apple Silicon, macOS 14.6 or later, an internet connection, and at least 6 GiB of free disk space**. Have your **Wallpaper Engine 2.8.42** installation files ready.

### 1. Install Rosetta 2

The Wine runtime uses Rosetta 2. If Rosetta is already installed, continue to the next step. Otherwise, open Terminal and run:

```sh
/usr/sbin/softwareupdate --install-rosetta
```

Follow the prompts to complete installation. See [Apple's Rosetta guide](https://support.apple.com/en-us/102527). Install Rosetta before starting the app's setup wizard.

### 2. Install Livewallpaper

Download `Livewallpaper-for-macOS-v2.0.0.dmg` from the [v2.0.0 release](https://github.com/Cold-T/LiveWallpaper-for-macOS/releases/tag/v2.0.0), open it, and drag `Livewallpaper for macOS.app` to **Applications**. Launch the app from Applications.

#### Allow the app to open

If macOS blocks the first launch with an “Apple could not verify” message:

1. Click **Done** in the alert.
2. Open **Apple menu → System Settings → Privacy & Security**.
3. Scroll down to **Security**. Find the message about **Livewallpaper for macOS** and click **Open Anyway**.
4. Authenticate if prompted, then click **Open** in the confirmation dialog.

Try launching the app from Applications first so its blocked-launch entry appears in Settings. These steps are also covered in [Apple's opening guide](https://support.apple.com/en-us/102445).

### 3. Set up the playback runtime

The first-launch wizard downloads three fixed archives from Sikarugir and Gcenx, about **448.5 MB** in total. It verifies their SHA-256 checksums and configures Wine, DXMT, and the media fixes. Keep the app open and connected to the internet until this step finishes.

### 4. Import Wallpaper Engine

Select your **Wallpaper Engine 2.8.42** installation folder or `wallpaper64.exe`. The wizard checks and copies the required engine files, prepares an isolated playback environment, and opens the wallpaper library. Existing configured environments open directly into the library.

In Settings, select a wallpaper folder, then choose a display and click a wallpaper to play it. Scene and Web projects use Wine; Video projects and local MP4/MOV files use the native macOS player. Adjust wallpaper volume from the toolbar or menu bar.

Workshop downloads additionally require Python, SteamCMD, and your own Steam login. See the [first-launch guide (Chinese)](docs/first-run-setup.zh-CN.md) for more setup details.

Runtime adapter sources, patches, build instructions, and license notices are available in the [source archive](https://github.com/Cold-T/LiveWallpaper-for-macOS/releases/tag/runtime-sources-v2.0.0).

## Build from source

Requires macOS, Python 3, Xcode and Apple Command Line Tools with the Swift compiler, and the yaml-cpp submodule. From this checkout:

```sh
git submodule update --init --recursive
python3 tools/build_wine_preview.py
```

This builds the frontend. Packaging the public online installer additionally requires the pinned setup recipe and runtime overlay; see the [setup build guide](docs/first-run-setup.zh-CN.md). The Windows engine is never included in the public package.

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

## Uninstall

Quit Livewallpaper, then run this command in Terminal to fetch and execute the uninstall script from GitHub:

```sh
curl -fsSL https://raw.githubusercontent.com/Cold-T/LiveWallpaper-for-macOS/SwiftUI/tools/uninstall-livewallpaper.sh | /bin/bash
```

The script asks whether to keep downloaded wallpapers (default: keep), lists the cleanup targets, and asks for confirmation. The app, managed runtime and selected downloads move to Trash; settings reset. Other wallpaper folders, original engine files and shared dependencies are preserved. Empty Trash to reclaim disk space.

To preview the cleanup:

```sh
curl -fsSL https://raw.githubusercontent.com/Cold-T/LiveWallpaper-for-macOS/SwiftUI/tools/uninstall-livewallpaper.sh | /bin/bash -s -- --dry-run
```

Optional flags: `--keep-wallpapers`, `--remove-wallpapers`, and `--yes`. With `--yes`, downloaded wallpapers are kept unless `--remove-wallpapers` is also supplied. Wallpaper removal covers the app’s default SteamWorkshop download folder.
