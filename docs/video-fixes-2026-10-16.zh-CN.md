# v14 播放链路修复与验收（2026-10-16）

以 v1.1.1 下载、管理和主界面接入原版 Wallpaper Engine 2.8.42。原本本地 LiveWallpaper-for-macOS 与 /Applications/LiveWallpaper.app 未修改。原版 EXE SHA256：`40e2ce021e9352324fadb3b8f72b8ba2a7ee95b71cc571d5b9f84be75cd993b0`。

## 此版修复

- MF source 音频请求不再阻塞视频取样；严格匹配 PE/Unix ABI。
- MediaEngine 真正执行循环，新视频段重置旧 EOS/待取样；保护正在进行的 seek。
- 用有界 CPU 输出缓存避免覆盖新帧前回读旧 GPU 纹理；source IMFMediaBuffer 在最终 COM 引用释放后安全复用。19.983 秒样本首轮从约55秒降至20.540秒，1199帧源交付19.928秒。随后8次无暂停循环约20～26秒，不能将其写为任何负载下精确实时。
- 渲染子 HWND 偶发保留2948×1946，而父 client 为2940×1912。验证标题、类、WinPID、完整 EXE 路径后，按真实父 client 正常 SetWindowPos 子窗；不改 Metal drawable 元数据或原版 EXE。实际错误现场已校正，后续自动回归也复现并自行恢复。
- 独立 Scene 窗口使用原引擎0x40b协议暂停/恢复，避免全局桌面命令未控制到 pop-out。
- 启动前核验三模块收据并同步旧 prefix PE；拒绝链接逃逸，失败回滚。完整哈希校验保留，FileProvider 元数据更新时间不再被当成 payload 变化。
- native Wine loader 复用同一 canonical ntdll。C realpath 避免 Foundation 将 /private/tmp 改写 /tmp 造成路径身份差异。
- 分离可控制的渲染窗口与真实首帧；启动阶段有界重试，播放后保留失败上限。监测在 CommonModes 持续运行。
- 发布包保留Unix可执行权限，实际解包后验证X_OK与严格代码签名。

## 最终选定模块

| 模块 | SHA256 |
|---|---|
| winegstreamer.dll | df9ce17519d944f68001e47ea4a16560b4f29e916bc9d13b0d712561c805a5ad |
| winegstreamer.so | d4e6e00c874ceb0f89ccabd3691c508499c443daa23979ef976a0a98e0e9d84a |
| mfmediaengine.dll | 2494d7755159acf4a25ed59fd8175a62e4c94b4123594a57e65f5ab61a8c3560 |

来源、LGPL许可、完整patch及构建入口在 playback/patches/source-pool-package/。没有采用有问题的 direct staging/stride v3/v4 候选。运行时内原版引擎缺失的2413个资源从用户原始压缩包补回，EXE保持原hash。

## 实测证据

- 最终三模块8/8轮生命周期通过：Minecraft Medium/High/Ultra；Elaina High；Hoshino Ultra；Cat&Bee、Subaru、LonelyCat Medium。全部窗口尺寸2940×1912；暂停末端FPS=0；恢复继续出帧；停止后无测试窗口/会话。
- build/workshop-tests/final-regression-round.json 保存逐轮结果。CUA实际看过Minecraft、Elaina、Hoshino、Cat&Bee、Subaru画面；未把窗口存在等同于视频正确。
- 真实v14主界面已点击Hoshino，观察到完整人物/吉他/背景/视频/粒子和文字，Stop确实移除PID78948；随后从同一主界面重播Minecraft，完整火焰、时钟和倒影正常；Stop移除PID79048。最终结果写入final-gui-validation.json。
- 27项Python测试通过；prefix同步29项双架构ASan/UBSan检查、窗口fit10项双架构检查、真实Wine/MF buffer16项契约检查另有收据。
- 所有实际测试静音，不改系统音量。测试保留coreaudio、在输出端清零；禁用音频驱动会导致视频纹理黑底，不能当成有效静音测试。真实GUI使用临时重导出静音守卫的测试桥，结束恢复生产桥。

## 本地交付

前端：dist/LiveWallpaper-Wine-preview-v14.zip，SHA256 `bd06c04720589dda0cc4346948bb78ab4822616703287cbe68e8fee08f2687d7`。应用1.1.1，内部build14。ZIP只包含前端与准备工具，不包含用户的专有引擎。

本机专用运行时：~/Library/Application Support/LiveWallpaper-Wine/Runtime-v14。主界面与运行时独立于原安装。Documents中的运行时副本只用于迁移诊断，最终使用Application Support，避免云目录延迟与Finder元数据污染签名。

## 仍不能宣称 Windows 全等的部分

没有Windows逐帧图像参考；未完成多屏、热插拔、长时间睡眠/恢复、所有作者参数/交互与实时媒体联动验收。mediaintegration仍关闭，Music/Spotify未读取。原生音量/缩放等控件尚非全部映射到Scene。此次修复与8轮成功不等于这些边界已经消失。

新增3款约735MB候选因SteamCMD需要重新登录而下载0B，未绕过登录。已完成素材按cleanup-journal删除，未完成扩展功能检查的样本保留；不要将其写成已通过全部功能。

本机已安装可直接启动的最终应用：`~/Library/Application Support/LiveWallpaper-Wine/LiveWallpaper Wine Preview.app`。严格签名验证通过，运行时与壁纸库已写入独立测试版偏好。测试守卫已移除，未留下/tmp动态库依赖。所有测试播放已停止。

本轮删除完成的Minecraft、Hoshino下载、导入链接及/tmp物理副本，累计8款完成素材已清理；其余9款仍保留待扩展功能检查。

## v15 个人一体包

`dist/LiveWallpaper-Personal-v15.zip`（811105541字节，SHA256 `2eae94ff228963facf42dcf925d1b0bd3556c6f5806fe4d51f30209a00b01ac8`）内含单个 `LiveWallpaper Personal.app`，包含原版引擎、Wine及现有修复组件。无需再选择外部运行时或导入引擎。首次启动自动校验解包到 Application Support，之后复用；壁纸素材独立下载。最低macOS14.6，Apple Silicon；未新增Intel支持。

本机已安装 `~/Library/Application Support/LiveWallpaper-Wine/LiveWallpaper Personal.app`。新包严格签名、ZIP CRC、内置归档SHA256、可执行权限检查通过；在有空格的永久安装路径验证首次解包和再次复用，不调用Wine/音频。播放核心与已验收v14字节一致，此轮仅包装和启动准备验收，没有重新声称全功能回归。

## v16 托盘恢复

托盘图标初始化、菜单顺序（开始/停止、显示主界面、下一个、退出）、快捷键与语言处理逐段对照v1.1.1一致。v15启动器替换为主程序内准备运行时，恢复主程序原生应用身份；移除空的SwiftUI Settings场景，避免新版macOS出现空白设置窗口。ContentView仍由NSHostingView承载。

最终一体包 `dist/LiveWallpaper-Personal-v16.zip`，SHA256 `8a57eea5820cdd65a44cace0f93d0db03bccaab29c0622e2de816ea1d24a7f18`。本机同路径应用已更新。CUA确认主界面正常、关窗后重新激活回到主界面、没有空白Settings窗口、点击原生退出菜单后进程退出。托盘菜单实现与图标资源采用v1.1.1原代码和资源；工具未直接点到系统托盘弹出菜单，因此不将源码一致写成每项托盘点击实测。ZIP CRC、可执行权限、前端哈希和严格签名均通过。媒体运行时未改变，本轮没有启动壁纸或声音。v15包已被本版取代。

## v17 输入快捷键与下载依赖

原生入口曾遗漏Edit主菜单，补回Undo/Redo、Cut/Copy/Paste/Delete/Select All，以nil target走标准responder chain。CUA在Workshop URL输入框实际执行Command-A、Command-C、Backspace、Command-V，完整链接恢复。用户截图Xcode错误由Finder启动的PATH选中系统Python shim引起，导入进程现在发现并优先使用本机已安装的Homebrew Python；另恢复直接调用的下载.sh脚本执行位。包内import_engine_project.py --help通过，无Xcode许可证报错；没有实际发起Workshop下载，不能宣称远端下载验收。该改动没有把Python本身加入应用，其他Mac仍需Python/SteamCMD等下载依赖。

本机应用已更新，包：dist/LiveWallpaper-Personal-v17.zip，SHA256 `f4ff12bb55aa180e795abb84ba86e9b612d564decdfa50930798e7c5a1ba286d`。ZIP CRC、脚本执行权限、shell语法、严格签名均已验证。未启动壁纸或音频。

## v18 修复红蓝通道颠倒

用户壁纸3470764447出现蓝紫肤色、黄色书封和暖色头发。直接解出作者白天视频并用ffmpeg解码作参考，原本为正常肤色、蓝书封与银蓝头发。实际MediaEngine诊断为output87/source87/destination28（BGRA→RGBA）；原先快速路径CopySubresourceRegion仅复制字节，未转换颜色。现在格式不一致时使用已有shader进行格式正确的转绘；shader输入先从同格式GPU样本复制，避免CPU回读。没有修改作者素材、显示器色温或原版EXE。

70秒静音循环播放及实际画面通过；另25秒夜间配置生命周期通过，但该轮截图未成功，不能称夜间视觉验收。最终v18主界面实际播放再次看到正常肤色/蓝书封/银蓝头发/暖色背景，首帧成功、尺寸错误0；Stop后PID88069退出。测试输出守卫已移除，正式桥与全部关键文件hash一致；用户壁纸选择已恢复，用户下载的壁纸保留。全部测试静音、系统音量未改。

完整Wine源包+combined+release+color三阶段patch以零fuzz应用，12个文件与公开源码快照一致。证据：build/color-fix-v18/validation.json。v18一体包SHA256 `55cc6c78d428d36cafe9002dc50bda5e31f6277cb374c46a3df3563fd05bcf75`，当前MediaEngine SHA256 `7489515c76741d614190443245c497601af5b82c87d92285ead178a189e076e7`。旧v14～v17多轮结果未包含本次颜色修复，不能据此声称那些轮次已通过正确色彩验收。

## v19 主界面无响应修复

现场采样确认重复启动进入stopPrefix后，主线程一直等待wineserver -w，而渲染器仍正常播放。现在对同一项目重复选择直接复用会话；停止先标记会话并终止其控制助手和渲染任务，再有界等待prefix退出，防止监测器重启助手。失败仍保留会话所有权以便重试。另外实际复测发现Documents目录枚举阻塞主线程，已将目录读取和项目探测移到后台。

15项ARM64 ASan/UBSan生命周期检查、既有停止失败/重试检查通过。实际v19主界面测试通过启动中重复点击、启动中停止、重新播放、播放中重复点击及打开设置；重复点击保留同一PID89474，首帧成功且尺寸错误0。测试全程静音、不改系统音量；结束恢复生产桥和用户原有桌面选择，保留用户壁纸3470764447。证据：build/ui-lifecycle-v19/validation.json。

本机同路径应用已更新v19；ZIP CRC、执行权限、严格签名和生产运行时关键hash验证通过。一体包SHA256 `40db2397ccf82733a38c8bed439f4b051485db9de4e808f45d639a0dffdafaf2`。运行时沿用v18颜色修复。
