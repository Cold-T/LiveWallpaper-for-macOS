# 首次启动安装向导

公开 v2.0.0 安装包采用在线配置：应用内附约 16 MB 的 DXMT、媒体修复、自有播放适配组件及许可文件；首次运行从原作者发布页下载固定版本 Wine 和媒体依赖。需要 Apple Silicon、macOS 14.6+、Rosetta 2、网络连接和至少 6 GiB 可用空间。播放环境配置不需要 Python 或 Xcode。

## 安装流程

1. 从 release 下载 `Livewallpaper-for-macOS-v2.0.0.zip`，解压并将应用移入“应用程序”。当前包为 ad-hoc 签名，未做 Apple 公证。
2. 首次启动自动下载三个原始归档，合计 448,508,856 bytes（约 448.5 MB），逐一检查大小与 SHA-256，再按文件清单组合运行时并安装修复组件。
3. 选择自己的 **Wallpaper Engine 2.8.42** 安装目录或 `wallpaper64.exe`。向导校验并复制引擎程序、assets、bin、plugins、thirdparty、ui、locale、distribution、原版 defaultprojects/templates 和启动辅助文件，不复制个人 projects/myprojects、Workshop 内容或原版 config.json。
4. 自动为显示器配置独立 Wine 前缀、字体、Retina、coreaudio 与媒体模块，完成后进入壁纸库。

已配置且可用的安装直接进入主界面。原引擎文件不会被改写。版本不符、文件缺失、校验失败、磁盘不足、并发安装和命令超时会显示错误，配置成功后才写入应用运行时设置。首次媒体初始化可能需要数十秒。

运行时位于 `~/Library/Application Support/LiveWallpaper-Wine/Setup`。已验证的组件缓存可复用；导入后的引擎和前缀位于 `R-<摘要前16位>`。安装与播放进程隐藏 Wine 的 Dock 图标、原版托盘和安装窗口。

首次配置默认静音，可通过主工具栏、设置和菜单栏调整音量。Workshop 下载仍另需 Python、SteamCMD 和自己的 Steam 登录；本向导负责播放环境。

## 固定下载来源

| 归档 | 原始发布来源 | SHA-256 |
| --- | --- | --- |
| WS12WineSikarugir11.0_1.tar.xz | [Sikarugir Engines](https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineSikarugir11.0_1.tar.xz) | `67e29fb3d74f363af39c69ba11f9b13a79812c5db07cf4748672658e4a200a0e` |
| Template-1.0.21.tar.xz | [Sikarugir Template](https://github.com/Sikarugir-App/Template/releases/download/v1.0/Template-1.0.21.tar.xz) | `bbe996e4e4375318485953d0c7818b7b4b0a4dc1f13303bcc584f99f7602f78d` |
| wine-stable-11.0_1-osx64.tar.xz | [Gcenx macOS Wine](https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.0_1/wine-stable-11.0_1-osx64.tar.xz) | `b50dc50ec7f41d58b115a6b685d4d1315ba3c797bd3aa0f49213f2703cb82388` |

这三个 vendor 归档不随本项目安装包再分发。应用内的 `RuntimeOverlay.tar.gz` 提供 DXMT（186a232）、Wine 媒体修复及自有适配组件；同 release 的 `Runtime-Adapter-Sources.tar.gz` 提供相关源码材料、补丁、构建说明和许可证。安装包不包含 Wallpaper Engine 或用户壁纸。

## 构建公开安装包

`tools/build_wine_preview.py` 构建前端。维护者使用已验证运行时与原版引擎生成校验清单，再由 `tools/build_online_setup_payload.py` 对照三个上游原始归档生成 schema 2 安装清单与 overlay。生成工具逐文件比对 SHA-256；vendor 文件必须能映射到原始归档成员，不能混入 overlay。详见该工具的 `--help`。

已有经验证的在线 payload 时：

```sh
python3 tools/build_wine_preview.py
python3 tools/build_setup_bundle.py \
  --app 'build/preview/Livewallpaper for macOS.app' \
  --payload /path/to/online-payload \
  --output dist/Livewallpaper-for-macOS-v2.0.0.zip
```

打包工具校验 overlay 哈希、归档路径、链接和文件来源唯一性，拒绝个人引擎一体包，使用 ditto 保留 macOS 包权限并生成 ZIP 与校验文件。源码包需要随正式安装包一起提供。

## 验证范围

Scene 壁纸已有实机播放、停止、重播和画面颜色回归记录；首次配置、原文件导入、菜单栏和音量控制均有本机验证。打包侧 40 项 Python 回归测试通过，在线 recipe 的全部 vendor 文件均与固定上游归档逐哈希匹配。

这些结果不代表所有壁纸、macOS 版本或显示器组合均已覆盖。Web / Video 工程覆盖有限；应用壁纸不自动执行；不支持锁屏播放，也不宣称与 Windows 完全一致。上游下载不可用时，首次安装需要恢复网络或等待上游恢复。
