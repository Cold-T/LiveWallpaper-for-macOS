# 统一壁纸音量控制

本机 build 201 在现有本地 AVPlayer 音量控制上，增加 Wine 播放进程的独立输出增益。设置页、主窗口扬声器弹窗和菜单栏图标菜单共用 `wallpapervolumeprecentage` / `wallpapervolume`。不修改系统设备音量。

Wine 启动前原子写入每个显示器会话的 `volume.txt`，并注入应用自带的 universal `wine_volume.dylib`。该模块只包装 `winecoreaudio.so` 的输出回调，保持原生产者和媒体时钟运行，在输出到设备前应用 0–1 增益。后台每 100 ms 读取最新设置，音频回调只读取原子值，不进行文件访问、锁、分配或日志。新建音频流、继承环境的 Web 子进程与 Scene/内嵌视频使用相同路径。非 Wine 音频回调不修改。

支持紧凑小端 PCM：float32/64、signed8/16/24/32、unsigned8、交错和非交错声道。Wine 没有设置 IsPacked 标志，故根据实际 stride 验证布局。音量文件暂时不可读保留上次有效值；启动时未读到有效值则保持零增益。上下文保留到进程退出，避免音频回调与释放竞争。

验证结果：
- 原生完整编译、链接及应用 deep/strict 签名通过。
- 37 个 Python 回归测试通过。
- 音量 C 测试在 ARM64 ASan/UBSan 和 x86_64 上通过：比例增益、零音量、100% 原样保留、正负整数、浮点、多缓冲区、无效输入、生产者持续调用和非 Wine 回调透传。测试不打开音频设备。
- 本机原壁纸 3470764447 实播日志确认 32-bit Wine 音频输出已挂接；窗口状态 firstFramePresented=1、rendererSizeMismatch=0。
- GUI 实测工具栏 0→1% 与设置页同步，再恢复 0%。菜单栏 slider 已加入菜单源码并通过完整编译，但本次自动化未能直接操作系统菜单栏入口。
- 合成 Web 测试未成功进入播放，尚未获得 Web 实际音频流的实测证据；不能据此声称所有 Web 壁纸已验证。测试目录已删除，原壁纸目录与播放记录已恢复。

安装位置保持原自用 app，未更改运行时校验哈希、商业引擎或系统音量；本轮未修改已发布的 GitHub v2.0.0。

## 后台播放器身份与托盘

`wine_app_identity.m` 与音量模块一起打包，仅在 LiveWallpaper 的桌面播放环境标记匹配时启用。将 Wine 请求的 Regular 激活策略改为 Accessory，使播放器不进入 Dock/应用切换器。原版托盘创建仍返回真实 NSStatusItem 供 Wine 正常更新和销毁，但强制 visible=NO，并阻止后续重新显示。原生前端不注入此模块，其菜单栏图标保持可用。

本机重启日志确认 `original tray suppressed visible=0`。原始 Wallpaper Engine 文件和运行时关键哈希不变。策略及可见性回调测试通过，universal 模块编译和应用签名验证通过。
