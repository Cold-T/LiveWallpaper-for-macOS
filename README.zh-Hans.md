> 当前为基于 v1.1.1 的 Wine 播放分支。保留下载、管理和菜单栏界面，接入原版 Wallpaper Engine。安装、构建及限制见 [接入与运行说明](docs/wine-playback.zh-CN.md)。

# Livewallpaper for macOS

**语言：** [English](README.md) | 简体中文

![LiveWallpaper](./Assets.xcassets/LiveWallpaperIcon.appiconset/icon_512x512.png)

LiveWallpaper 是一个面向 macOS 14+ 的开源动态壁纸应用。

## 项目目的

项目目的很简单：让视频动态壁纸在 macOS 上更好用。当前分支支持原生本地视频播放，并通过 Wine 播放导入的 Wallpaper Engine 项目；菜单栏、壁纸管理和下载界面沿用 v1.1.1。

本项目基于 [thusvill/LiveWallpaperMacOS](https://github.com/thusvill/LiveWallpaperMacOS) 的 release 源进行整理和改造，并在此基础上加入当前 SwiftUI 界面、状态栏流程和 Workshop 导入功能。

LiveWallpaper 与 Wallpaper Engine Team、Valve、Steam 或任何 Steam Workshop 创作者没有从属、赞助、背书或官方合作关系。

## Workshop 导入

LiveWallpaper 通过 `steamcmd` 下载 Workshop 项目，并以 `.weproject` 库条目保留完整项目。Scene / Web / Video 项目路由到原版引擎；裸 `.mp4` / `.mov` 仍使用原生播放器。Scene 已有实机验证，Web / Video 项目的覆盖范围仍有限，应用壁纸不自动执行。

下载功能需要 Python、SteamCMD 及自己的 Steam 登录；这些下载依赖尚未全部内置。

请只通过你自己的 Steam 账号使用你有权访问的 Workshop 内容。LiveWallpaper 不内置、不托管、也不再分发 Workshop 内容；用户需要自行遵守 Steam 条款以及每个 Workshop 项目的许可或创作者授权。

## 安装 v2.0.0

从 [v2.0.0 Releases](https://github.com/Cold-T/LiveWallpaper-for-macOS/releases/tag/v2.0.0) 下载 `Livewallpaper-for-macOS-v2.0.0.zip`，解压后将 `Livewallpaper for macOS.app` 移入“应用程序”。需要 Apple Silicon、macOS 14.6 及以上；当前包为 ad-hoc 签名，未做 Apple 公证。

公开发行包包含前端、原生辅助程序、播放适配组件及选定 Wine 媒体补丁源码，不包含商业 Wallpaper Engine、完整 Wine/DXMT 运行时或壁纸素材。裸 MP4/MOV 可直接播放；Scene/Web 项目需要使用自己的引擎安装与免费兼容层准备外部运行时，再在设置中选择运行时目录。步骤与验证范围见 [运行说明](docs/wine-playback.zh-CN.md)。

Workshop 下载另需 Python、SteamCMD 和自己的 Steam 登录。之前的本机个人一体包属于独立的自用构建，不是本次公开下载文件。

## 从源码编译

需要 macOS、Python 3、Xcode 和 Apple Command Line Tools（含 Swift 编译器）及 yaml-cpp 子模块。从当前检出目录运行：

```sh
git submodule update --init --recursive
python3 tools/build_wine_preview.py
```

该命令构建前端预览，不下载或包含 Windows 引擎。外部运行时准备与个人一体包构建见 [接入与运行说明](docs/wine-playback.zh-CN.md)。

## 使用

在设置中选择壁纸文件夹。点击壁纸缩略图后，会在所选显示器播放；菜单栏可停止、切换壁纸或重新打开主界面。文件夹和文件名可包含空格。

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



## 许可证

LiveWallpaper 以 GNU General Public License version 3 or later 发布。许可和归属信息请参见 [LICENSE](LICENSE)、[NOTICE](NOTICE)、[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 和 [CONTRIBUTORS.md](CONTRIBUTORS.md)。

## Credits

[Wallpaper Engine](https://icons8.com/icon/jQspry5Tmnu5/wallpaper-engine) icon by [Icons8](https://icons8.com).
