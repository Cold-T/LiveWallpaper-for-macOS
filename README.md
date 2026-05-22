
# LiveWallpaper App for macOS 14+

**Languages:** English | [简体中文](README.zh-Hans.md)

![LiveWallpaper](./Assets.xcassets/LiveWallpaperIcon.appiconset/icon_512x512.png)

LiveWallpaper is an open-source live wallpaper app for macOS 14+.

## Purpose

The goal is simple: make video wallpapers feel practical on macOS. The app focuses on local video wallpapers, menu bar controls, multi-display handling, and importing compatible video items from Steam Wallpaper Engine Workshop.

This project is based on the release source of [thusvill/LiveWallpaperMacOS](https://github.com/thusvill/LiveWallpaperMacOS), then adjusted for the current SwiftUI app, status bar workflow, and Workshop import features.

LiveWallpaper is not affiliated with, endorsed by, or sponsored by Wallpaper Engine Team, Valve, Steam, or any Steam Workshop creator.

## Workshop import

LiveWallpaper can use `steamcmd` to download a Steam Wallpaper Engine Workshop item, then import a directly available `.mp4` or `.mov` video into the local wallpaper folder.

Only video wallpapers are supported right now. `scene.pkg`, web wallpapers, application wallpapers, and other Wallpaper Engine project types are not supported yet.

Use Workshop content only through your own Steam account and only when you have the right to access it. LiveWallpaper does not include, host, or redistribute Workshop content; users are responsible for complying with Steam's terms and each Workshop item's license or creator permissions.

## Installation

Download the latest `LiveWallpaper.dmg` from [Releases](https://github.com/Cold-T/LiveWallpaper/releases), open it, and move `LiveWallpaper.app` to `Applications`.

## Build from source
- macOS 14+
- git
- Xcode

Run:

```sh
git clone https://github.com/Cold-T/LiveWallpaper.git
cd LiveWallpaper
xcodebuild -project LiveWallpaper.xcodeproj -scheme LiveWallpaper -configuration Release -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

## Guide for DMG Installation

> [!IMPORTANT]
> ## If macOS says “LiveWallpaper.app” is damaged and cannot be opened
> This release is not notarized, so Gatekeeper may block the first launch.
> After moving the app to `Applications`, run:
> 
> `xattr -d com.apple.quarantine /Applications/LiveWallpaper.app` 

Click the "Show in Finder" button to open the wallpaper folder, then place wallpapers in it.

> [!NOTE]
> Make sure the selected folder path doesn't include spaces.
>
> File names should avoid extra dots except the dot before the extension.
> 
> ## Eg:
> 
>  - file.1920x1080.mp4 ❌ ('.'s > 1)
> 
>  - file-1920x1080.mp4 ✅ ('.'s = 1)

> [!NOTE]
> Workshop import and playback currently support video items only: `.mp4` and `.mov`.

> https://github.com/user-attachments/assets/3d82e07d-b6b9-4a7d-b6de-5dd05dff3128

## Bug reports

Post bugs with result of following command.

 `/Applications/LiveWallpaper.app/Contents/MacOS/LiveWallpaper` 

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


<!-- ## Gallery
> <img width="185" height="134" alt="Screenshot 2025-11-30 at 1 52 01 PM" src="https://github.com/user-attachments/assets/0c91fb29-e729-485b-8f93-7080aed68881" />
> <img width="185" height="134" alt="Screenshot 2025-11-30 at 1 51 53 PM" src="https://github.com/user-attachments/assets/7848d2fd-8cc4-4271-a4c0-2868bdf00422" />
 



> ![Screenshot 2025-05-15 at 6 46 35 AM](https://github.com/user-attachments/assets/167b0c08-454f-4d53-9e65-8798aed6459f)

> <img width="2560" height="1600" alt="Screenshot 2025-11-30 at 1 52 34 PM" src="https://github.com/user-attachments/assets/79a24ed8-cc5a-4246-87d0-9c93e04766f2" />

> <img width="2560" height="1600" alt="Screenshot 2025-11-30 at 1 54 35 PM" src="https://github.com/user-attachments/assets/10466b02-77d5-4814-9fb7-a865e62a41ba" />

 

> https://github.com/user-attachments/assets/748c7078-1f99-4182-876f-08aa59d2bc63 -->
 

## License

LiveWallpaper is distributed under the GNU General Public License version 3 or later. See [LICENSE](LICENSE), [NOTICE](NOTICE), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), and [CONTRIBUTORS.md](CONTRIBUTORS.md).

## Credits

[Wallpaper Engine](https://icons8.com/icon/jQspry5Tmnu5/wallpaper-engine) icon by [Icons8](https://icons8.com).
