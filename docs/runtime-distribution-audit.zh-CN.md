# 在线安装与适配层分发范围

公开 Setup 使用在线来源方案：首次运行从发布者下载固定 Wine、Template 和 Gcenx 归档，校验归档 SHA-256，再按清单提取并验证逐文件哈希。项目不把这些 vendor 归档、框架、原生库和字体重新打包上传。Wallpaper Engine 由用户从自己的 2.8.42 安装目录导入，程序和资源文件沿用原作者许可。个人配置和用户壁纸独立保存。

| 用户机器直接下载的来源 | 固定归档 SHA-256 |
| --- | --- |
| [Sikarugir WS12 Wine11.0 revision1](https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineSikarugir11.0_1.tar.xz) | `67e29fb3d74f363af39c69ba11f9b13a79812c5db07cf4748672658e4a200a0e` |
| [Template1.0.21](https://github.com/Sikarugir-App/Template/releases/download/v1.0/Template-1.0.21.tar.xz) | `bbe996e4e4375318485953d0c7818b7b4b0a4dc1f13303bcc584f99f7602f78d` |
| [Gcenx Wine11.0_1 原生库来源](https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.0_1/wine-stable-11.0_1-osx64.tar.xz) | `b50dc50ec7f41d58b115a6b685d4d1315ba3c797bd3aa0f49213f2703cb82388` |

安装清单 `SetupRuntime.json` 是归档成员映射及逐文件校验的依据。历史个人离线包 `FreeRuntime.tar.gz` 不作为公开在线方案的资产；它的技术校验结果不能代替来源材料。

## 本项目分发的适配层

- DXMT 五个图形模块：固定 commit `186a2327f1ec76376f6bc1ef64636f08b0728567`，LGPL-2.1-or-later。源码包含固定 NVAPI 与 mingw-directx-headers 子模块及其独立许可证。
- 三个 Wine 媒体模块：`winegstreamer.dll`、`winegstreamer.so`、`mfmediaengine.dll`，LGPL-2.1-or-later。来自 Wine11 commit `db11d0fe6a169c457e23d007e20404643d067aa8`，应用完整 combined、release delta、color-format 三项补丁；最终选择由 `release-candidate-schema1.json` 记录。
- 桌面桥接、音量、窗口身份与控制辅助程序：本仓库源码及 GPL-3.0-or-later 许可。

应用携带适配层完整许可证与归属说明。同一 release 提供 `Runtime-Adapter-Sources.tar.gz`，含精确上游输入、完整修补后源码、补丁、构建脚本、测试及校验清单。重建可能因时间戳、调试路径和签名产生不同二进制字节；源码匹配不等于已完成可重复二进制构建。

## 来源核对的边界

该包不宣称覆盖 publisher vendor 二进制的完整对应源码。此前检查未建立 Sikarugir revision1 的全部 vendor 修改与构建流程；Template GStreamer 的版本后缀也不能仅凭上游标签推定一致。这些组件改为从发布者固定链接获取，并保留来源，不以未确认的候选源码替代。

字体跟随 vendor 下载，适配层不重新分发字体。已检查的兼容名称 msyh、arial、tahoma 等包含 WenQuanYi/Google、Liberation、Wine 来源；不能根据兼容文件名判断其作者。安装时保留来源文件的版权和许可信息。
