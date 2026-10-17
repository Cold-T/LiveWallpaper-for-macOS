> 当前为基于 v1.1.1 的 Wine 播放分支。保留下载、管理和菜单栏界面，接入原版 Wallpaper Engine。安装、构建及限制见 [接入与运行说明](docs/wine-playback.zh-CN.md)。

# Livewallpaper for macOS

**语言：** [English](README.md) | 简体中文

![LiveWallpaper](./Assets.xcassets/LiveWallpaperIcon.appiconset/icon_512x512.png)

LiveWallpaper 是一个面向 macOS 14.6+、Apple Silicon Mac 的开源动态壁纸应用。

## 项目目的

项目目的很简单：让视频动态壁纸在 macOS 上更好用。当前分支支持原生本地视频播放，并通过 Wine 播放导入的 Wallpaper Engine 项目；菜单栏、壁纸管理和下载界面沿用 v1.1.1。

本项目基于 [thusvill/LiveWallpaperMacOS](https://github.com/thusvill/LiveWallpaperMacOS) 的 release 源进行整理和改造，并在此基础上加入当前 SwiftUI 界面、状态栏流程和 Workshop 导入功能。

LiveWallpaper 与 Wallpaper Engine Team、Valve、Steam 或任何 Steam Workshop 创作者没有从属、赞助、背书或官方合作关系。

## Workshop 导入

LiveWallpaper 通过 `steamcmd` 下载 Workshop 项目，并以 `.weproject` 库条目保留完整项目。Scene / Web / Video 项目路由到原版引擎；裸 `.mp4` / `.mov` 仍使用原生播放器。Scene 已有实机验证，Web / Video 项目的覆盖范围仍有限，应用壁纸不自动执行。

下载功能需要 Python、SteamCMD 及自己的 Steam 登录；这些下载依赖尚未全部内置。

请只通过你自己的 Steam 账号使用你有权访问的 Workshop 内容。LiveWallpaper 不内置、不托管、也不再分发 Workshop 内容；用户需要自行遵守 Steam 条款以及每个 Workshop 项目的许可或创作者授权。

## 安装 v2.0.0

从 [v2.0.0 Releases](https://github.com/Cold-T/LiveWallpaper-for-macOS/releases/tag/v2.0.0) 下载 `Livewallpaper-for-macOS-v2.0.0.zip`，解压后将 `Livewallpaper for macOS.app` 移入“应用程序”。需要 Apple Silicon、macOS 14.6 及以上、Rosetta 2 和至少 6 GiB 可用空间；当前包为 ad-hoc 签名，未做 Apple 公证。

首次启动会从 Sikarugir 和 Gcenx 的 GitHub 原始发布页自动下载三个固定版本归档，合计约 448.5 MB，逐一校验 SHA-256 后组合 Wine 运行时并应用 DXMT 与媒体修复。应用内附约 16 MB 的运行时适配组件及许可文件，不包含商业 Wallpaper Engine 或壁纸。

选择自己的 **Wallpaper Engine 2.8.42** 安装目录或 `wallpaper64.exe`，向导自动校验、导入文件并配置独立播放环境，完成后进入壁纸库。原文件不会被改写；已有可用环境会自动跳过配置。播放环境安装不需要 Python 或 Xcode；Workshop 下载另需 Python、SteamCMD 和自己的 Steam 登录。详见 [首次启动说明](docs/first-run-setup.zh-CN.md)。

同一 release 的 `Runtime-Adapter-Sources.tar.gz` 提供随包适配组件的源码材料、补丁、构建说明和许可文件。Vendor Wine 与媒体框架归档由首次安装流程直接从各自上游发布页下载。

## 从源码编译

需要 macOS、Python 3、Xcode 和 Apple Command Line Tools（含 Swift 编译器）及 yaml-cpp 子模块。从当前检出目录运行：

```sh
git submodule update --init --recursive
python3 tools/build_wine_preview.py
```

该命令构建前端。公开在线安装包还需固定安装清单和适配组件 overlay，构建方法见 [首次启动说明](docs/first-run-setup.zh-CN.md)。公开包不包含 Windows 引擎。

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

## 卸载

从 Release 下载 `uninstall-livewallpaper.command`，运行 `bash ~/Downloads/uninstall-livewallpaper.command`。脚本会先列出目标并询问确认；添加 `--dry-run` 可仅预览。请先从菜单栏退出应用。脚本将应用和专用 Wine、DXMT、媒体组件、引擎导入副本移到废纸篓，并重置设置；保留壁纸、原始引擎及共享依赖。清空废纸篓后释放空间。不需要 sudo 或 Python。
