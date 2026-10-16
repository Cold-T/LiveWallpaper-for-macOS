# 兼容性修复记录（2026-10-15，测试版 build 9）

工作仅在独立 `LiveWallpaper-Wine` 中进行。原有 `LiveWallpaper-for-macOS` 未修改，原播放器 PID 5987 保持运行。全部播放测试使用静音的专用 Wine 前缀。

## 修复与证据

| 问题 | 根因与处理 | 验证状态 |
| --- | --- | --- |
| Lonely Cat 时钟数字和日期缺失 | 原引擎直接查找 Windows Fonts/consola.ttf，Wine 字体替换表无法满足。缺失时从引擎自带 RobotoMono-Regular.ttf 提供回退文件，已有字体保留 | Wine 10 候选中 CUA 实见完整 `05:13` 和 `Thursday, 15 October`；Wine 11 待回归 |
| 屋顶猫媒体接口异常 | Wine 不提供 Windows 系统媒体会话接口；启动前关闭引擎 `general.user.mediaintegration` | Wine 10 中观察超过一分钟，原接口激活错误和 c0000409 未重现。此处理禁用曲名、封面读取，并未实现 macOS 媒体信息 |
| Elaina 视频纹理崩溃、黑屏 | DXMT 0.80 共享纹理依赖 Wine >=10.18；Wine 10.0 不满足。0.71 降级又缺少 KEYEDMUTEX，软件解码开关未解决。改用 Wine 11 + 包含真实锁和 Metal SharedEvent 的官方 DXMT main 完整构建，并补齐 GStreamer H.264 解码依赖 | 新组合已启动，原 DeviceTexture 和 KEYEDMUTEX 错误未重现；**锁屏阻断画面验证，尚不能标记视频修复完成** |
| Wine 11 直接启动静默退出 | 此发行版 ntdll 检查 `SikarugirAppWine11`；核对官方 Template 1.0.21 启动器后复现其环境赋值 `1` | 隔离 Wine 11 wineboot 升级和静音注册均 exit 0，原版引擎已启动并建立桌面窗口 |
| 引擎错误弹窗仍被误判为活跃 | 桌面桥接发现本进程可见的 Wine Error 窗口后报告错误，原生监督器停止此显示器的专用前缀并报告日志位置 | 已编译；尚已用隔离静音错误窗口夹具确认原生报错、专用前缀清理和目标窗口消失；原版真实崩溃复现另需覆盖 |

字体回退的字形、字宽可能不同于 Consolas。未修改任何 Workshop 项目、PKG、Windows EXE 或 DLL 中的授权逻辑。

## 运行时

- 免费 Sikarugir Wine 11.0 revision 1，原始来源保持不变。
- [DXMT 官方 CI run 38211702924](https://github.com/3Shain/dxmt/actions/runs/38211702924)，提交 `186a2327f1ec76376f6bc1ef64636f08b0728567`，artifact `11730076177`。替换完整 x86_64 d3d11、dxgi、d3d10core、winemetal DLL 和 winemetal.so。
- [Sikarugir Template 1.0.21](https://github.com/Sikarugir-App/Template/releases/tag/v1.0) 的完整 x86_64 GStreamer.framework，归档 SHA256 `bbe996e4e4375318485953d0c7818b7b4b0a4dc1f13303bcc584f99f7602f78d`。原生 `avdec_h264` 自检 exit 0；未安装系统包或启动该 Template 应用。
- 私有插件路径、scanner 和每个前缀单独的 GStreamer registry，避免依赖系统编解码器。
- 原版 `wallpaper64.exe` SHA256 始终为 `40e2ce021e9352324fadb3b8f72b8ba2a7ee95b71cc571d5b9f84be75cd993b0`。

`tools/prepare_wine_runtime.py` 现可复制完整 GStreamer 和指定 DXMT 集合，记录实际来源与组件哈希；`playback/WineCompatibility.h` 在每次启动前准备字体和兼容配置，不依赖 Python。

## 验证记录与未完成项

- 4 项导入回归通过；原生兼容准备测试通过，包括配置保留、已有字体保留、字体目录越界拒绝。
- 原生测试版已构建；临时目录中的签名及严格验证通过。发布 ZIP 不包含 Windows 引擎或兼容层运行时。
- Wine 11 视频候选日志与窗口状态：`build/compat-fixes/wine11-main-video-candidate/`。桌面层 `-2147483623`，1470×956，鼠标穿透。
- GStreamer 仍有格式协商 caps 警告；现有证据不能判定其对最终视频输出的影响。
- 必须解锁后检查 Elaina 主体视频及持续运动，并在 Wine 11 上回归 Lonely Cat、屋顶猫、三体和安和昴的画面与切换。未完成这些验证前，不能把五款全部标为兼容。

## 本地调查索引

| 结论 | 证据类型 | 本地证据 |
| --- | --- | --- |
| 字体直接文件访问 | 原版 EXE 定点反汇编 + 运行画面 | `build/clock-investigation/` |
| 媒体开关 | 原版 JS + 配置 A/B 日志 | `build/media-investigation/`、`build/workshop-tests/logs/media-disabled/` |
| 视频为 H.264 | TEX 格式提取 + 首帧无声解码 | `build/video-investigation/` |
| 旧共享句柄失败 | minidump + DXMT 上游源码 | `build/compat-fixes/crash-analysis.json`、`build/dxmt-investigation/` |
| Wine 11 启动环境 | 官方 ntdll 与启动器的交叉反汇编 + 实际启动 | `build/wine11-diagnostics/`、`build/compat-fixes/wine11-official-env.log` |
| GStreamer 可用性 | 原生 CLI、ABI 检查 | `build/gst-diagnostics/` |

Wine 11 环境标记的结论来自官方已发布二进制；未在公开源码找到该标记，不能称为公开源码验证。上述日志、minidump 和下载文件只保留本地。


## build 8：按原版行为继续修复

以下结论来自当前代码、原始资源与实际 Wine 运行；不把窗口存在等同于画面正确。

| 项目 | 当前处理 | 已确认与限制 |
| --- | --- | --- |
| Retina 清晰度 | 读取显示器 backingScaleFactor，在已停止且注册表已落盘的专用前缀写入 RetinaMode；原引擎窗口参数同步使用像素尺寸 | 实测 Metal drawable 从 1470×956 升至 2940×1912，桌面窗口仍为 1470×956 点 |
| 原版画质预设 | 按原版 getQualityPreset 的完整值实现 Low/Medium/High/Ultra；无设置时补齐首次向导的 Medium，保留已有选择；测试可显式选择档位 | 原版 Medium 是 15 FPS，High 是 25，Ultra 是 30；不能把 Medium 的 15 FPS 当作兼容故障 |
| 字体一致性 | 优先链接本机已安装、文件名完全匹配的真实 Windows 字体；仅缺失 Consolas 时保留引擎自带字体回退 | 本机找到 Office 中真实 Consolas 等六个字体文件。未分发字体，也未写入源字体；Wine 11 最终字形待解锁检查 |
| Vulkan 加载 | 使用官方 Template 的匹配 loader 与 MoltenVK，并统一 GStreamer 与 Wine 到同一实际驱动文件 | 视频回归中 loader 缺失与 MVKBlockObserver 重复类警告均消失；caps 协商警告仍在调查 |
| 停止与切换 | 分开执行专用前缀 wineserver -k 和 -w，等待注册表落盘；停止失败时保留会话并拒绝继续启动 | 组合 -k -w 不会等待；原始 Wine 代码与实际空前缀返回值已核对。当前回归停止后目标窗口不存在 |
| 初始锁屏状态 | 监督器启动即读取会话锁屏状态，再处理后续锁屏通知 | 新测试记录 locked=true；锁屏中不会把恢复请求记作已恢复播放 |
| 桌面交互候选 | 鼠标事件仅在露出的桌面转给原版 Wine 鼠标处理器，屏蔽前景窗口、未知接收者和锁屏；保持系统点击穿透 | 仍需解锁完成鼠标和交互壁纸检查，当前默认未启用，不代表交互已修复 |
| macOS 媒体桥候选 | 独立 WinRT 接口桥及 Music/Spotify 本地 backend；正常运行时仍禁用不支持的媒体集成 | 独立 Wine 契约实测标题、封面流与 A→B 事件回调成功；未访问真实播放器、未请求自动化权限、未注册到普通运行时。尚未达到 Windows 系统全部媒体会话能力 |

### 扩大样本与清理规则

在原先五款之外，新增十二款完整 Workshop 项目，覆盖 H.264/HDR 视频、3D、交互角色、时间变化与 7680×2160 超宽画面，共十七款。下载结果保存在 `build/workshop-tests/downloads-round2.json`，独立测试库以符号链接导入。

`rounds-v11` 是早期启动检查，`rounds-v12` 保留修复统一驱动之前的证据，`rounds-v13` 是统一驱动后的 Medium/High/Ultra 三轮。每个结果单独记录初始锁屏、暂停状态、实际呈现次数、像素尺寸、停止后窗口与日志。**锁屏期间的结果仅覆盖加载、渲染表面和生命周期，不验收视觉、运动、鼠标或 Windows 一致性。**

清理工具 `tools/cleanup_workshop_tests.py` 只接受私有测试目录中的清单，只清理显式标记 testing_complete 的项目及其匹配导入链接；先验证整批路径，再删除。未完成视觉/功能检查的项目保持待测，不自动以启动成功标记完成。保留诊断日志，完成后的测试内容按用户要求删除，普通壁纸库与原有项目不在清理范围。

新增测试覆盖字体保留、注册表幂等与越界拒绝、预设保留和选择、桌面输入边界、清理路径与整批中止。Python 导入和清理测试合计八项通过；build 8 原生编译与暂存目录严格签名验证通过。全程使用 Audio 为空的静音前缀，因此音频输出和音频响应未验收。

### 剩余日志的真实调用定位

只读 opt-in Gst hook 保留原参数、原返回值及原 critical，只为非 fixed caps 输出元数据和栈，未抓取媒体样本。Elaina 的十次报错均来自 `winegstreamer.so +0x1D35` 和 `+0x9244`：`pad_added_cb` 查询候选能力集后内联调用 `caps_is_compressed`，后者经 `wg_format_from_caps` 错把未定 raw-video 能力集交给 `gst_video_info_from_caps`。本批栈未落到实际输出或缓冲池创建，不能由此证明所有视频画面正确。最小候选是在 Wine 的压缩类型判断中直接识别 raw MIME，保留后续具体输出格式协商；尚待可重建 ABI 与隔离 A/B。

DXMT 的 swap effect 3/backbuffer 2 警告并非交换链创建失败，源码仍返回成功；但索引、历史内容和 Present1 参数支持不完整。尚无证据表明此版本引擎依赖这些未实现行为，也不能直接修改其请求为 discard 来掩盖差异。保留为需要图像和调用证据的覆盖缺口。

完成的 Deep Space 与 Arsenal 内置样例测试导入链接已经删除；引擎自带资源保留。新增下载的十七款仍待视觉验收，不标记完成。记录：`build/workshop-tests/completed-builtin-import-cleanup.json`。


## 本轮最终非视觉验证（build 9）

- 十七款下载壁纸 × Medium/High/Ultra：**51/51 生命周期检查通过**，停止后目标窗口残留 0。所有案例开始时均处于锁屏；这不是画面、运动或交互验收。完整结果与摘要：`build/workshop-tests/rounds-v14/`。
- 三款视频相关项目 × 三档画质：重建的 GStreamer Unix 模块通过 **9/9** 定向回归，确认每次实际加载候选，caps critical 全为 0，原模块在 A/B 期间哈希不变。随后备份原模块并在私有 runtime11 使用修复模块，普通原生播放路径再次确认 2940×1912、无 caps critical、干净停止，无需诊断 hook。
- 源码来自经哈希核对的 Wine 11.0，commit `db11d0fe6a169c457e23d007e20404643d067aa8`。仅修改 raw MIME 压缩分类。补丁已保存为 `playback/patches/wine11-raw-caps-classification.patch`；251 个导入、直接依赖/版本、native/WoW64 两组 37 项调用表已核对。候选与供应商 PE 的全部私有结构布局仍未逐字段证明，视觉仍待解锁。重建报告：`build/wine-gst-rebuild/rebuild-report.md`。
- 模块 SHA256 `f03c9a593781042975dcdc4a39126dd9e61f5c86764d5b16bdc85fc4b9c9c596`；原模块备份 `build/compat-fixes/winegstreamer-vendor-stock.so`，原 SHA256 `27fd335a37e108d85c6ead4e2d9db3163ba4fda328a6e129a3eb78400e6a88b0`。准备工具可显式接收 `--wine-gstreamer-unix` 和必需的 `--wine-gstreamer-sha256`，检查架构与哈希并原子替换私有目标，保留原始输入文件。
- 媒体桥从原版 helper 实测修复泛型事件 IID、缺失的 DataReader，以及已驻留封面的立即读取路径。原版 helper 输出 A/B 各一套曲名、不同 PNG 封面、播放状态和进度，合计八帧；DataReader 原版调用形态、未知流异步读取、大小端/UTF16/关闭测试通过。新 bridge 不修改 Windows helper 文件。证据：`build/media-bridge/helper-consumer-resident/`。
- 原引擎会发送 type6 只读 blocklist 配置完成初始会话查询；单独宿主需要模拟这一条消息。没有通过伪造 WinRT 会话变化解决初始发现。该启动路径的当前会话已存在、初始无会话后 A→B 两组检查均通过；分别收到一套和两套媒体数据，标题没有重复，未发送真实媒体控制或 AppleEvents。宿主最终使用有边界的自有子进程强制退出，不能称为原版 helper 优雅退出验证。
- **正常播放路径仍未接入真实媒体 backend**，`mediaintegration=false` 仍是临时避免不支持接口的策略。合成数据测试不是 Music/Spotify 功能完成。已提出新的 macOS 自动化读取授权请求，收到答复并解锁前不访问真实播放器。
- build 9 原生编译、临时目录严格签名和发布 ZIP 检查通过。为避免 FileProvider 修改中间对象元数据引发 Swift 构建输入变化，中间文件和模块缓存现统一放在 `/private/tmp`；未修改系统工具或安装系统开发包。ZIP 不含 Windows EXE/DLL、Wine/GStreamer 运行时或 Office 字体。

当前唯一可以确认的结论是上述范围内的代码和生命周期验证。图像、持续运动、桌面输入、媒体真实来源、音频响应、Windows 参考对照，以及 DXMT 顺序交换链警告的实际覆盖仍需完成。Mac 锁屏阻断 CUA 画面检查，不能标记全部壁纸已通过或 Windows 行为完全一致。测试完成的导入已清理，十七款下载案例尚待视觉验收后删除。


### 交换链和暂停追加定位

暂停命令的原版发送与接收侧已逐分支核对：`pause` / `play` 是全局 IPC 命令，通过 WM_COPYDATA 设置/清除全局 bit0，再遍历 renderer map 下发布尔值。没有窗口标题参数分支，因此保留当前 CLI，不凭提交计数增加未经证实的 `-window` 参数。具体模拟时间是否暂停仍需运行功能检查。地址和反汇编证据：`build/clock-investigation/pause-control-findings.md`。

独立静音 prefix 的 DXGI 诊断使用精确 CI DLL 哈希和八个槽位校验，只临时修改进程内方法指针，完整原 DLL 文件不变；结束后恢复 prefix DLL，运行时原 DLL 哈希不变。无图形转发 fixture 验证参数、返回值、LastError、对象/资源身份及嵌套分类。第一次 fixture 遇到 Rosetta 的 libiconv 签名补充附加失败并超时，未安装代理；改用正式 WinePlayer 入口和无图形所需最小库路径后通过。未修改系统 Rosetta 缓存或保护。

初始锁屏诊断的三个案例只捕获到 GetBuffer，未覆盖渲染，不用于判断 Present。随后仅在诊断探针明确覆盖初始暂停策略以采样 API（不解锁、不读取像素，不修改产品策略）；时钟和三体分别捕获 336、370 次外部 Present1，GetBuffer 均只取索引0、调用成功。所有 Present1 的脏矩形数和滚动指针均为0；未调用当前 backbuffer 索引。视频的短时含暂停诊断未捕获呈现，须用连续播放与恢复原 DLL 基线补查，不能把窗口成功判作渲染通过。日志均未达到2048事件上限，强制停止没有最终汇总时，以上次数只表示完整观察窗口内已记录调用。证据：`build/dxgi-trace-diagnostics/runtime-2/`、`runtime-3/`。

这些是有边界的临时插桩证据，不是完全无观察影响的证明；确认为 Present1 后不能再描述为 Present-only。未观察到非零脏矩形等行为不能证明 buffer preservation 或 Windows 像素等价。暂不为消除警告改写 swap effect 或 buffer count。


视频连续45秒检查捕获535次 Present1（均成功，dirty/scroll为空），Metal实际呈现524帧、2940×1912；恢复原加载路径后613帧、停止无残留，但该次 drawable 变成2948×1946而桌面窗口仍1470×956。此差异尚未修复，不能据此声称插桩与基线无差异；正在重复采集仅尺寸的元数据，调查原生窗口/Wine后端尺寸同步。结果：`build/dxgi-trace-diagnostics/runtime-4/coverage.json`。这两次专用诊断均有意覆盖初始锁屏暂停、关闭合成sleep阶段，不能计为产品锁屏策略验收。


尺寸复测补充：原桥加只读尺寸字段的三次连续视频基线均为2940×1912，因此先前2948×1946偏差尚未稳定复现。最小修正是在首次桌面适配或原生窗口几何变化时，即使外框已等于屏幕，也同步 Wine 的 frame 缓存，并在 orderFront 后调用它自己的 `windowDidResize:nil skipSizeMove:YES`，向 Windows 后端传递最终尺寸；不直接改 CAMetalLayer/backbuffer，不持续逐帧发送。

修正候选的视频、三体、时钟三款30秒检查均为2940×1912（分别428、437、443帧），窗口/内容/子视图/Metal层尺寸一致，停止后无残留；两款另采的 Windows WindowRect/ClientRect均为2940×1912，style0x94000000，无caption/border/thickframe。因此不能把之前8×34直接归因为已证实的 Windows 装饰边距。普通运行时接入后，视频30秒429帧、2940×1912、无残留。已备份旧桥并接入新桥，准备工具对新编译的自有桥执行ad-hoc签名与严格验证，未重签供应商DLL或修改Windows引擎。源链路、时序边界、元数据和回归结果在 `build/dimension-investigation/`。原偏差是间歇现象，现有结果不足以宣称彻底消除，后续仍需更多轮和画面检查。

已签名最终模块的普通路径复查也通过：2940×1912，实际呈现 283 帧，停止后会话和窗口为0。当前 bridge SHA256 `1ceea539e72d65619e132db8047b573d1dbceed76c0dd16da70b8e6702be5748`。本轮所有测试播放继续使用 Audio 为空的独立前缀；17款下载仍未完成视觉验收，清理工具 dry run 返回空列表，未把仅窗口/元数据通过的壁纸误标为测试完成。


## 解锁后的视觉回归：KVO 窗口识别修复

实际观察 Wine 窗口触发 AppKit KVO 后，旧桥把 `NSKVONotifying_LWDesktop_WineWindow` 拒绝为未知类，停止写 heartbeat，导致原生监督器停止播放。旧 setter 按实时 superclass 寻找原 IMP，在 KVO 层级变化时也有递归风险。

新桥保留系统窗口的 isa 和 KVO 类身份，沿祖先识别 WineWindow，对精确选中的窗口标记策略。类本地 setter 包装捕获安装前的原 IMP；未选中窗口原样转发，不改继承的 NSWindow Method。原生测试覆盖适配前/后 KVO、缓存 setter 的通知、移除观察者、非目标窗口及 autorelease/dealloc；ARM 和 x86_64/Rosetta 均退出0。

诊断正常层可激活窗口已连续观察时钟壁纸的字体、日期、水波和粒子变化，观察期间 heartbeat 保持更新，累计2516帧，停止后无会话/窗口残留。诊断窗口不代表产品桌面输入验证。修复桥已备份旧模块并接入私有 runtime，SHA256 `5a17181114dc06b9dfaa5b24f1030e969eab2d1f7a8fe16c31a93bea70459fc7`；普通桌面路径回归待本轮视觉检查后执行。

视频首帧检查发现启动阶段黑屏；时间线首帧27.35秒，46.14秒累计236帧。因此不能把启动截图称为持续黑屏，也不能仅凭计数判定图像正常，正在出帧后重测。

为隔离一次 Rosetta libgnutls AOT 附件错误，诊断把17个原样依赖副本置于 /private/tmp 并仅对测试 renderer 提前搜索该目录。时钟诊断实际载入该 libgnutls；未改供应商原文件、系统缓存或安全设置，错误根因未定。可观察 QA bundle 仍有外链 ntdll 的严格封装限制；另建纯物理 QA bundle 严格签名通过，但尚未用于真实运行，NLS/子进程身份仍有边界。两者都不是发布包的部署结论。


## 十七款画面检查与视频静音测试修正

解锁后的正常层 QA 窗口检查已覆盖17款：13款观察到完整图像和持续运动；伊蕾娜、星野的视频背景仍黑，Minecraft 场景全白，土星仍复现 drawable 2948×1946 与目标2940×1912不符。三档51次生命周期通过不能替代这些画面结果。瑞鹤图中央空框经资源解析确认是作者纹理装饰，不能当作缺字修复。土星结果也说明先前尺寸同步修正尚未彻底解决间歇偏差。

视频黑屏追踪观察到 Media Foundation 在解码前拒绝含未绑定音频输出节点的 topology，HRESULT 0xc00d521b。测试前缀的 Audio="" 会移除音频设备，是当前失败的重要测试条件；尚未通过恢复设备后的真实画面 A/B，不能声称已修好视频。定位记录：`build/video-black-investigation/topology-failure/findings.md`。Minecraft 内嵌视频离线解析是8位SDR AVC，不能只因标题含HDR而断定硬件HDR输出失败。

新增仅供诊断的 `playback/diagnostics/silent_coreaudio.c`，在 Wine HAL 渲染回调安装时包装原生产者并清零全部输出缓冲，同时保留音频时钟；拒绝输入总线启用、输入回调、未保护实例启动、MIDI 图启动与保护期间格式变更。实例释放后撤销启动许可。`tests/test_silent_coreaudio.c` 对全部硬件API使用桩，在ARM和x86_64/Rosetta均通过，覆盖首回调、多缓冲、生产者错误、8位无符号静音及实例地址复用。此结果不等于真实音频设备运行验证，也未接入发布版。

真实静音复测前两次被Rosetta供应商库AOT附件错误阻断，第三次处于锁屏且无可用主显示器，未启动渲染；所有尝试均已恢复私有测试前缀 Audio=""。为隔离原路径问题，把95个原样依赖文件复制至临时目录，校验原始字节，并仅为诊断覆盖Vulkan加载路径；未修改供应商原库、系统缓存、安全设置或系统音量。复制凭据：`build/video-black-investigation/root-native-dependency-copies.json`。该隔离方式尚待真实运行确认。

已清理完成当前静音画面与三档生命周期测试的6款任务下载副本及其导入符号链接：3509243656、3521337568、3463520581、3441006668、3278399262、3354366708。保留测试日志和观察记录；异常、媒体、交互或长时间变化待测案例继续保留。清理工具的8项导入/路径保护测试通过，清理清单为 `build/workshop-tests/cleanup-journal.json`。上述完成范围不代表Windows像素一致或全部作者功能验收。


### 后续运行状态更正

`silent-hw-on-5` 在桌面权限可用后创建了目标窗口，`saturn-geometry-1` 使用 Audio="" 加同一静音层与只读尺寸探针作对照；两者初始 locked=true，均未输出首帧，已清洁停止并恢复配置。另用不受沙箱限制的只读 AppKit/CoreGraphics 检查确认 sessionAvailable=true、screenLocked=true、onConsole=true、loginDone=true、前台 com.apple.loginwindow、显示器1。Finder后台AX/截图不能证明物理桌面解锁。此前沙箱内启动失败还混有桌面访问缺失；不能把这些运行归为有效的解锁视觉复测，也不能仅据loader_section等待认定静音层死锁。线程采样与只读源码复查尚无静音hook直接死锁证据。详见 `build/video-black-investigation/silent-startup-review.md` 和各轮 interpretation.json。

尺寸配对探针原生x86_64 dylib已编译并签名；先前等待的PE编译也已产出72704字节PE32+ x86-64 helper。尚未执行握手采样，仅表示编译产物可用，不能宣称尺寸根因已确认。采样使用序号与前后稳定Win32几何窗口，不声称跨线程原子或同一Present帧。说明与源码：`build/dimension-investigation/paired-probe/README.md`。


### 2026-10-16：首帧阻塞与文件读取超时

`silent-hw-on-6` 确认初始解锁，全部采样未锁屏，但280秒内仍无呈现，也未出现静音输出保护注册；这是有效的解锁启动失败，尚未证明与静音hook的因果关系。`saturn-baseline-2` 禁用Wine音频并完全移除静音dylib，同样未出首帧；147.67秒收到锁屏后按产品策略暂停，不能计作完整画面验收。

普通桌面入口 `prod-staged-saturn-1` 明确记录原路径bridge mmap errno60；因此有客观文件读取超时，不只是疑似Rosetta问题。把29个Unix模块与同哈希新桥复制到诊断临时搜索目录（保留ntdll原路径以免改变Wine路径推导），另把土星project.json/scene.pkg原样复制到临时目录，均记录字节数/哈希。随后 `prod-staged-saturn-2` 创建普通桌面窗口，但初始已锁屏，0帧不用于视觉验收。所有自有测试均清洁停止；Audio=""恢复，供应商原文件未重签/修改。凭据为 `build/video-black-investigation/unix-native-dependency-copies.json`、`build/dimension-investigation/saturn-asset-stage.json`。

静音层新增控制路径write(2)入口/拒绝/返回标记，实时渲染回调没有日志。全部静音与输入禁止guard保留；新增写失败errno及RT无日志的纯stub验证，ARM和x86_64/Rosetta均通过，新候选严格签名通过。尚未实跑带标记候选，不能宣称真实输出回调已验证。后续测试脚本在单个测试子进程存活期间使用caffeinate防止显示器空闲休眠，退出即结束，不改锁屏偏好，也不解锁当前会话或阻止用户手动锁屏。继续真实画面测试仍需手动解锁。


### 2026-10-16：有效视频画面与取样停滞定位

缩小 renderer 的原生依赖覆盖至17个同字节 GnuTLS 依赖后，时钟壁纸恢复实际画面与持续运动；先前全根目录 DYLD_LIBRARY_PATH 对照不作为渲染基线。测试仍使用正常层 QA 窗口，尚不能替代普通桌面路径验收。

供应商 Wine 实际创建 Apple DefaultOutput（`def `），而非公开 Wine 源码所用 HALOutput。诊断静音层增加对 DefaultOutput 的严格允许条件：回调必须来自 winecoreaudio.so，保留原生产者调用，再清零全部输出；输入禁止与未保护实例拒绝启动继续生效。控制路径标记确认真实注册、初始化和启动成功。新增实时原子计数，实时回调没有日志、锁或内存分配。ARM及x86_64/Rosetta桩测试通过。未修改系统音量、未授权媒体或输入权限。

伊蕾娜3326873240恢复完整视频图像，观察到人物嘴部变化、时钟秒数及粒子运动；使用受保护 DefaultOutput 的重复测试成功并清洁停止。尚未完成全日夜切换，故保留测试资源。

星野3510729512关闭引擎视频硬件加速后恢复完整人物、吉他和窗景，但视频样本随后停止，粒子与 Present 仍增长，不能算动画通过。静音音频回调也持续增长，因此不是单凭回调停止可解释。MF trace 显示音频 stream 进入 wait_on_sample 后占住唯一 source 工作队列，后续视频请求留在队列中；系统时钟查询仍继续。最后视频PTS为9.633秒，具体Unix等待分支尚未获得原生栈证明。证据：`build/video-black-investigation/hoshino-mf-clock-trace-1/static-clock-analysis/`。

原供应商 GStreamer 模块已从备份恢复到临时单文件搜索目录，SHA256 `27fd335a37e108d85c6ead4e2d9db3163ba4fda328a6e129a3eb78400e6a88b0`。`hoshino-stock-gst-2` dyld日志确认实际加载临时原模块，仍在464个视频输出样本后停止，期间呈现与静音回调继续。因此定格并非仅由重编Unix模块引入；没有把重编模块全部私有ABI等价当作已证明事实。原runtime模块未在该对照中替换。

修复候选并行核对原引擎自带后端和MF非阻塞取样调度。不能通过丢帧、无限缓存或只改多线程队列宣称解决：Stop、seek、EOS及buffer身份必须一并验证。所有本轮已结束的测试均恢复私有前缀 Audio=""；日志保留，未完成案例不删除。


### 媒体源修复候选与循环缺口（尚未验收）

新增完整上游Wine11补丁 `playback/patches/wine-11.0-mf-source-nonblocking.patch`：保留控制串行队列，以每流FIFO及有限非阻塞读取避免音频等待挡住视频；原子复制/释放与flush代次校验保护帧身份。匹配PE+Unix共38槽，旧37槽顺序不变，必须成对使用。11项真实函数体合成缓冲测试、32/64位ABI编译及独立审查通过。冻结模块与源码/构建收据见 `build/wine-mf-fix/`；并非仅换so。

第一轮成对实机输出完整1199个视频样本，但片尾截图为黑，未证明首帧回归。未改媒体源的公共PE基线能呈现完整图像但再次冻结。后续发现在Documents的多个文件出现errno60、项目读取空、cryptbase/mpr加载失败；将测试壁纸、Wine核心与测试前缀置于普通临时目录后，候选完整图像在持续呈现后仍可见，两个流EOS与MESessionEnded事件链完整。此处只能撤回此前对“首帧黑图”的判定，不能将所有早期黑图直接归为单一原因。

物理测试前缀复制保留必需注册表和原字体符号链接，内置组件使用同版本已缓存物理副本；112个没有可读物理来源的可选旧前缀文件未复制并记入收据。该目录是诊断环境，不是完整发布运行时。临时Wine副本的wine.inf复制mtime曾触发额外初始化，已恢复原mtime与对应私有前缀时间戳；不把此初始化行为当作引擎回归。

实际原EXE给MediaEngine调用SetLoop(TRUE)，随后依赖其自动重播；Wine11仅保存标志，片尾仍发送ENDED。MF trace证实原引擎收到结束后按自己的状态暂停取帧。新增循环候选 `wine-11.0-mfmediaengine-loop.patch` 沿既有seek/Start路径重播并抑制循环中的ENDED，9项COM桩测试通过。第一次联合实机确实触发Start(0)，但仍未输出第二轮：进一步发现video_frame_sink的eos只置true、从不复位，导致新段的RequestSample被永久抑制。正在修复正确新段边界；目前不能声称循环已通过。

所有已结束模块对照在finally恢复原始PE与Unix字节，私有测试音频配置恢复禁用；原EXE、系统音量及原安装播放器未变。单独的source-only路由候选已构建并留存，不曾部署或改COM注册。
