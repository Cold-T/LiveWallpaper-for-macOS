# macOS 14+ 动态壁纸应用 LiveWallpaper

**语言：** [English](README.md) | 简体中文

![LiveWallpaper](./Assets.xcassets/LiveWallpaperIcon.appiconset/icon_512x512.png)

LiveWallpaper 是一个面向 macOS 14+ 的开源动态壁纸应用。

## 项目目的

项目目的很简单：让视频动态壁纸在 macOS 上更好用。当前重点是本地视频壁纸、菜单栏控制、多显示器处理，以及导入兼容的 Steam Wallpaper Engine Workshop 视频项目。

本项目基于 [thusvill/LiveWallpaperMacOS](https://github.com/thusvill/LiveWallpaperMacOS) 的 release 源进行整理和改造，并在此基础上加入当前 SwiftUI 界面、状态栏流程和 Workshop 导入功能。

LiveWallpaper 与 Wallpaper Engine Team、Valve、Steam 或任何 Steam Workshop 创作者没有从属、赞助、背书或官方合作关系。

## Workshop 导入

LiveWallpaper 可以通过 `steamcmd` 下载 Steam Wallpaper Engine Workshop 项目，然后把其中直接可用的 `.mp4` 或 `.mov` 视频导入到本地壁纸文件夹。

目前只支持视频壁纸。`scene.pkg`、网页壁纸、应用壁纸，以及其他 Wallpaper Engine 项目类型暂时不支持。

请只通过你自己的 Steam 账号使用你有权访问的 Workshop 内容。LiveWallpaper 不内置、不托管、也不再分发 Workshop 内容；用户需要自行遵守 Steam 条款以及每个 Workshop 项目的许可或创作者授权。

## 安装

从 [Releases](https://github.com/Cold-T/LiveWallpaper/releases) 下载最新的 `LiveWallpaper.dmg`，打开后将 `LiveWallpaper.app` 移到 `Applications`。

## 从源码编译

- macOS 14+
- git
- Xcode

运行：

```sh
git clone https://github.com/Cold-T/LiveWallpaper.git
cd LiveWallpaper
xcodebuild -project LiveWallpaper.xcodeproj -scheme LiveWallpaper -configuration Release -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

## DMG 安装指南

> [!IMPORTANT]
> ## 如果 macOS 提示 “LiveWallpaper.app” 已损坏，无法打开
> 当前发布包没有做 notarization，首次启动可能会被 Gatekeeper 拦截。
> 将应用移到 `Applications` 后运行：
>
> `xattr -d com.apple.quarantine /Applications/LiveWallpaper.app`

点击 “在 Finder 中显示” 按钮会打开壁纸文件夹，你可以把壁纸文件放进去。

> [!NOTE]
> 请选择的文件夹路径不要包含空格。
>
> 文件名中尽量不要包含多个点号（扩展名的点号除外）。
>
> ## 例如：
>
> - file.1920x1080.mp4 ❌（点号数量 > 1）
> - file-1920x1080.mp4 ✅（点号数量 = 1）

> [!NOTE]
> Workshop 导入和播放目前只支持视频项目：`.mp4` 和 `.mov`。

> https://github.com/user-attachments/assets/3d82e07d-b6b9-4a7d-b6de-5dd05dff3128

## 图库

> ![Application](./asset/application.png)

> ## 这是静态图片，目前 LiveWallpaper 不支持锁屏播放视频。
> ![lockscreen](./asset/lockscreen.png)

> ![settings](./asset/settings.png)

> https://github.com/user-attachments/assets/36fb169e-b7cc-4489-9459-dab07c8dd2c6

> # 性能
> ![p1](./asset/preformance1.png)
> ![p2](./asset/preformance2.png)
> ![p3](./asset/preformance3.png)
> # 多显示器支持

> https://github.com/user-attachments/assets/9575873c-79e6-4eba-a7a5-9408b2cc4ed0

<!--
## 图库
> <img width="185" height="134" alt="Screenshot 2025-11-30 at 1 52 01 PM" src="https://github.com/user-attachments/assets/0c91fb29-e729-485b-8f93-7080aed68881" />
> <img width="185" height="134" alt="Screenshot 2025-11-30 at 1 51 53 PM" src="https://github.com/user-attachments/assets/7848d2fd-8cc4-4271-a4c0-2868bdf00422" />

> ![Screenshot 2025-05-15 at 6 46 35 AM](https://github.com/user-attachments/assets/167b0c08-454f-4d53-9e65-8798aed6459f)

> <img width="2560" height="1600" alt="Screenshot 2025-11-30 at 1 52 34 PM" src="https://github.com/user-attachments/assets/79a24ed8-cc5a-4246-87d0-9c93e04766f2" />

> <img width="2560" height="1600" alt="Screenshot 2025-11-30 at 1 54 35 PM" src="https://github.com/user-attachments/assets/10466b02-77d5-4814-9fb7-a865e62a41ba" />

> https://github.com/user-attachments/assets/748c7078-1f99-4182-876f-08aa59d2bc63
-->

## 许可证

LiveWallpaper 以 GNU General Public License version 3 or later 发布。许可和归属信息请参见 [LICENSE](LICENSE)、[NOTICE](NOTICE)、[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 和 [CONTRIBUTORS.md](CONTRIBUTORS.md)。

## Credits

[Wallpaper Engine](https://icons8.com/icon/jQspry5Tmnu5/wallpaper-engine) icon by [Icons8](https://icons8.com).
