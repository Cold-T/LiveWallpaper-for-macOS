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

LiveWallpaper 通过 `steamcmd` 下载 Workshop 项目，并以 `.weproject` 库条目保留完整项目。Scene / Web 项目路由到原版引擎；Video 项目与裸 `.mp4` / `.mov` 使用 v1.1.1 的 macOS 原生播放器。Scene 已有实机验证，Web / Video 项目的覆盖范围仍有限，应用壁纸不自动执行。

下载功能需要 Python、SteamCMD 及自己的 Steam 登录；这些下载依赖尚未全部内置。

请只通过你自己的 Steam 账号使用你有权访问的 Workshop 内容。LiveWallpaper 不内置、不托管、也不再分发 Workshop 内容；用户需要自行遵守 Steam 条款以及每个 Workshop 项目的许可或创作者授权。

## 安装 v2.0.1

系统要求：**Apple Silicon、macOS 14.6 及以上、网络连接和至少 6 GiB 可用空间**。

### 1. 安装 Rosetta 2

Wine 运行时需要 Rosetta 2。已安装的用户可继续下一步；首次安装请打开“终端”，运行：

```sh
/usr/sbin/softwareupdate --install-rosetta
```

按终端提示完成安装，再启动应用的配置向导。详见 [Apple 的 Rosetta 安装说明](https://support.apple.com/zh-cn/102527)。

### 2. 安装 Livewallpaper

从 [v2.0.1 Releases](https://github.com/Cold-T/LiveWallpaper-for-macOS/releases/tag/v2.0.1) 下载 `Livewallpaper-for-macOS-v2.0.1.dmg`，打开后将 `Livewallpaper for macOS.app` 拖到 **Applications / 应用程序**，再从“应用程序”启动。

#### 允许首次打开

首次启动若出现“Apple 无法验证”提示：

1. 在提示框点击 **完成（Done）**。
2. 打开 **苹果菜单 → 系统设置 → 隐私与安全性（Privacy & Security）**。
3. 向下滚动到 **安全性（Security）**，找到 **Livewallpaper for macOS** 被阻止的提示，点击 **仍要打开（Open Anyway）**。
4. 按提示验证身份，再在确认框点击 **打开（Open）**。

请先从“应用程序”尝试启动一次，系统设置才会显示对应的拦截记录。详见 [Apple 的打开应用说明](https://support.apple.com/zh-cn/102445)。

### 3. 配置播放环境

首次启动向导会从 Sikarugir 和 Gcenx 下载三个固定版本归档，合计约 **448.5 MB**，校验 SHA-256 后配置 Wine、DXMT 和媒体修复。请保持应用打开和网络连接，等待组件准备完成。

### 4. 完成播放配置

组件内置版会自动校验并配置 **Wallpaper Engine 2.8.42** 播放文件。如果当前版本显示“选择 Wallpaper Engine”，请选择自己的 2.8.42 安装目录或 `wallpaper64.exe`。向导会校验并复制文件到独立环境，随后进入壁纸库。已有配置好的环境会直接进入壁纸库。

重新安装后，应用会自动将保留的 Workshop 下载恢复到默认壁纸库。库入口保存在 `~/Library/Application Support/LiveWallpaper/ImportedWallpapers`，下载原文件保存在 `~/Library/Application Support/LiveWallpaper/SteamWorkshop/steamapps/workshop/content/431960`。也可在设置中选择其他壁纸文件夹，再选择显示器并点击壁纸播放。Scene 和 Web 项目使用 Wine；Video 项目及本地 MP4/MOV 使用 macOS 原生播放器。音量可在工具栏或菜单栏调整。

Workshop 下载另需 Python、SteamCMD 和自己的 Steam 登录。更多配置细节见 [首次启动说明](docs/first-run-setup.zh-CN.md)。

适配组件的源码、补丁、构建说明和许可证见[独立源码归档](https://github.com/Cold-T/LiveWallpaper-for-macOS/releases/tag/runtime-sources-v2.0.0)。

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

先退出 Livewallpaper，再在“终端”运行以下命令，直接从 GitHub 获取并执行卸载脚本：

```sh
curl -fsSL https://raw.githubusercontent.com/Cold-T/LiveWallpaper-for-macOS/SwiftUI/tools/uninstall-livewallpaper.sh | /bin/bash
```

脚本会询问是否保留已下载壁纸（默认保留），列出清理目标，再确认卸载。应用、专用运行时和选择删除的下载壁纸会移到废纸篓，设置会重置。其他壁纸文件夹、原始引擎及共享依赖会保留。清空废纸篓后释放空间。

仅预览清理内容：

```sh
curl -fsSL https://raw.githubusercontent.com/Cold-T/LiveWallpaper-for-macOS/SwiftUI/tools/uninstall-livewallpaper.sh | /bin/bash -s -- --dry-run
```

可选参数：`--keep-wallpapers`、`--remove-wallpapers` 和 `--yes`。`--yes` 默认保留壁纸，配合 `--remove-wallpapers` 才会删除。壁纸删除范围为应用默认 SteamWorkshop 下载目录。
