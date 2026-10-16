# v1.1.1 接入原版 Wallpaper Engine 播放

独立目录 `LiveWallpaper-Wine`，分支 `wine-playback`，基线标签 `v1.1.1` / `4c9b359`。
现有 `LiveWallpaper-for-macOS` 的本地开发版未迁移、未修改。

## 路径

- 保留 v1.1.1 SwiftUI 主界面、显示器选择、SteamCMD 登录、下载取消和集合导入流程。
- 下载的 Scene / Web / Video 保留完整项目目录，以 `<id>.weproject` 作为库条目；默认仍使用符号链接。
- 点击项目：原版 wallpaper64.exe → Wine → DXMT → Metal → 原生 Wine 窗口 → macOS 桌面层。最新修复候选为 Wine 11.0 revision 1 / DXMT 官方主分支构建 `186a2327`，详见[兼容性修复记录](compatibility-fixes-2026-10-15.zh-CN.md)。
- 只为明确命名的播放窗口添加原生适配，保持 Finder 图标层在其上方；鼠标穿透、不抢焦点、跨 Space。
- 每个显示器 UUID 使用独立 Wine prefix。切换、停止和退出只关闭应用自己启动的 prefix，不使用全局 killall。
- 原有裸 MP4/MOV 文件继续使用 v1.1.1 原生视频播放器。
- 测试版使用独立 bundle ID、通知名和 `LiveWallpaper-Wine.yaml`，不覆盖已安装版本。

## v2.0.0 公开发行

公开下载为 `Livewallpaper-for-macOS-v2.0.0.zip`，内含 `Livewallpaper for macOS.app`，适用于 Apple Silicon、macOS 14.6 及以上。包内包含前端、辅助程序、适配源码和媒体补丁源码；不含 Wallpaper Engine、完整 Wine/DXMT 或壁纸。裸 MP4/MOV 可直接使用；引擎项目需要按下方步骤准备外部运行时，再在设置中选择该运行时根目录。

下载功能另需 Python、SteamCMD 和 Steam 登录。本机先前使用的个人包内置专用运行时，是独立的本地构建，不随公开发行上传。其缓存仍位于 Application Support；公开版内部配置域继续保留，以便沿用现有库和播放设置。

## 构建与运行

以下命令在当前检出目录执行；需要 Xcode、Apple Command Line Tools、Python 3 及 yaml-cpp 子模块。Python 可执行路径因机器安装位置不同而异。

```sh
git submodule update --init --recursive
```

```sh
/opt/homebrew/bin/python3.13 tools/build_wine_preview.py
```

首次准备运行时需要本人的原版 Windows 安装和先前已验证的免费 Wine/DXMT 文件。工具只复制到新目录，不修改原安装：

```sh
/opt/homebrew/bin/python3.13 tools/prepare_wine_runtime.py \
  --engine ../wallpaper_engine \
  --wine ../reverse-engineering-results/macos-desktop-presentation/runtime-probe/free-wine/wswine.bundle \
  --fallback '../reverse-engineering-results/macos-desktop-presentation/runtime-probe/Wine Stable.app/Contents/Resources/wine/lib' \
  --gstreamer build/compat-fixes/template/Template-1.0.21.app/Contents/Frameworks/GStreamer.framework \
  --dxmt build/compat-fixes/dxmt-main-ci/186a2327f1ec76376f6bc1ef64636f08b0728567 \
  --output build/runtime-new
```

设置中选择准备后的目录。准备工具会对比原始及复制后 EXE 的 SHA256，记录实际组件来源和哈希，复制完整 GStreamer 与配套 DXMT；仅调整副本的兼容配置，不修改 EXE、Steam DLL 或授权逻辑。原程序不纳入 Git；普通前端预览包不含引擎。个人一体包由本机另行构建，包含选定运行时。

本机源码构建入口为 `tools/run_wine_preview.command`。它默认使用当前修复候选 `build/runtime11`、`build/library` 和 `build/state11`。支持导入的项目也可以直接放在所选壁纸库目录的一级子目录中。

个人一体包使用已编译前端和已验证运行时生成，不会自动下载组件。`--work` 必须指向尚不存在的独立工作目录：

```sh
python3 tools/build_personal_bundle.py \
  --frontend 'build/preview/LiveWallpaper Wine.app' \
  --runtime '/path/to/verified-runtime' \
  --work '/private/tmp/livewallpaper-personal-new' \
  --version 19 \
  --output dist/LiveWallpaper-Personal-v19.zip
```

目录 `playback/patches/source-pool-package/` 保存选定 Wine 媒体模块的源码、补丁、许可与重建入口。`build/` 和 `dist/` 为本机构建、验证及交付产物，均不进入 Git。历史验证证据不应作为当前版本全功能通过的证明。

## 验证与边界

发行校验记录见 `docs/release-v2.0.0.json`；历史本机详细日志保留在工作区，不随公开源码上传。v18修复BGRA/RGBA传递导致的红蓝颠倒；v19修复重复选择壁纸时的无限退出等待和主线程目录枚举。分版本证据见 [修复与验收记录](video-fixes-2026-10-16.zh-CN.md)。

初次初始化 Wine prefix 会比后续播放慢，当前启动超时为 90 秒。运行日志位于状态目录下 `<显示器 UUID>/playback.log`，原生窗口状态为同目录 `window.json`。窗口状态表示进程和桌面适配存在，不代表帧率或每个特效均正确。

原生视频的音量、缩放、低功耗选项尚未映射到原版 Scene 播放器。后者目前按原引擎配置播放。自动暂停使用官方 pause/play 命令；多显示器、睡眠恢复和热插拔需要独立实机验证，不能由实现代码推定已通过。Web/Video 原项目已接入路由，但仍需类型兼容性测试。应用壁纸不自动执行。

运行时准备工具面向当前已验证组件，不是通用 Wine 安装器。测试版不提供 Windows 引擎下载、自动购买或许可证处理。

参考：官方命令行接口 https://help.wallpaperengine.io/en/functionality/cli.html 。


本轮 Wine 11、Retina、原版画质、字体与视频模块修复及验证范围见 [兼容性修复记录](compatibility-fixes-2026-10-15.zh-CN.md)。准备工具的实验性 `--wine-gstreamer-unix` 必须同时指定 `--wine-gstreamer-sha256`，仅用于经核对的私有运行时模块。媒体桥和桌面交互仍在独立验证，普通播放尚未启用，真实媒体访问需单独的 macOS 自动化授权。
