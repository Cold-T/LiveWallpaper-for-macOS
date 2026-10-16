# Windows.Media.Control 媒体桥：独立实验组件

目标是让原版 Wallpaper Engine 消费真实 macOS 媒体数据。组件已具备可测试的 PE 契约和 native transport；**尚未通过真实播放器授权与 Windows 表现对照，不等于已经实现 Windows 全功能无差异**。此目录没有修改或注册到运行中的 Wine，也没有请求系统权限。

## 实现范围

- 原生 Music / Spotify AppleScript 后端：真实曲名、作者、专辑、播放状态、时长和进度。Music 返回真实 JPEG/PNG 封面bytes；Spotify 返回实际封面URL，broker可显式 `--fetch-artwork` 下载HTTPS真实图片，失败时不造封面。
- 原生播放、暂停、切歌和seek。只有已授权且明确指定的播放器会接收命令；回执表示AppleEvent完成，真实状态回读仍待系统测试。
- PE激活工厂、RequestAsync / IAsyncInfo、选定session、标准IVectorView / IIterable / IIterator、metadata / playback / timeline对象。未知optional字段为空，不实现的record / channel / repeat / shuffle / playback-rate等命令返回false，能力标志关闭。
- Manager与Session事件注册/移除、快照变化派发。使用准确typed-handler IID通过RoGetAgileReference / Resolve跨apartment调用；注册失败返回实际HRESULT。
- Genres为空的标准只读WinRT集合（native来源未提供genres），不伪造曲风。
- Thumbnail返回真实图片的IRandomAccessStreamReference，OpenReadAsync / IRandomAccessStreamWithContentType / IRandomAccessStream / IInputStream / IClosable，支持Seek/Clone/read-only GetInputStreamAt与ReadAsync。图片数据随properties对象保留，避免后续封面覆盖旧snapshot。
- 本地原子快照/封面文件与私有0700目录的异步命令req/ack。错误、超时、未知目标、缺权限不返回假成功；已开始或结果不明的命令不自动重试，避免重复切歌。
- 所有PE vtable方法可通过 `LWMEDIA_TRACE=1` 打印方法名与HRESULT，不输出歌曲、文件路径或参数。

## 能力与权限边界

当前仅表示用户选定的Music或Spotify来源，GetSessions返回该范围内0/1个session，**不代表macOS全部播放器枚举或系统当前session优先级**。浏览器、任意第三方播放器、Windows AppUserModelId映射、全部Windows控制功能仍未覆盖。原生bundle ID作为稳定source ID，不能假称与Windows AUMID相同。

默认inventory/fixture不发送AppleEvents。真实查询/控制必须指定播放器和 `--allow-automation`，并已具备Automation授权。缺权限时返回 `automation_permission_required`，查询不会隐式请求权限或启动播放器。

首次授权需要用户审查后，由主应用通过NSWorkspace/LaunchServices启动独立helper.app的 `--request-permission --player music|spotify`，以helper应用身份提示；不要从Codex/Terminal直接触发首次授权并要求用户给终端权限。实际TCC显示身份仍须在用户确认的系统提示中核对。没有使用Accessibility注入、MediaRemote私有权限或系统Perl身份变通。

Helper有明确bundle ID `local.livewallpaper.media-helper` 和NSAppleEventsUsageDescription。当前为本机ad-hoc签名；分发需稳定开发者签名，若启用Hardened Runtime应配置AppleEvents相关entitlement，但entitlement不代替用户TCC授权。

## 构建与已执行的离线检查

```sh
sh playback/media_bridge/build_native.sh
sh playback/media_bridge/build_pe.sh
/opt/homebrew/bin/python3.13 -m unittest discover -s playback/media_bridge/tests -v
build/media-bridge/lwmedia-helper --self-test
```

官方llvm-mingw20261006工具链仅放在build/toolchains，归档SHA256 `a7a19b11048e89372637d26279cdb7c430ed3cf8c1e224310421312bf986ebf6`，未全局安装。

产物在build/media-bridge：lwmedia-winrt.dll、lwmedia-contract-probe.exe、lwmedia-helper，以及LiveWallpaper-Media-Helper.zip。Documents FileProvider会自动附加FinderInfo，故通过不含扩展属性的ZIP交付；构建脚本在/private/tmp解压严格验签，路径见native-build.json。

本代理只执行编译、静态ABI检查、fixture/模拟transport测试和不发AppleEvents的helper保护检查。未运行任何Wine/PE或真实AppleEvents。主线程隔离prefix测试必须单独记录，不把fixture当真实媒体通过。

## 主线程隔离fixture契约验证

生成明确标记的合成session与8x8 PNG：

```sh
/opt/homebrew/bin/python3.13 playback/media_bridge/tests/write_fixture.py \
  --output build/media-bridge/contract-session.bin --generation 1 --phase A
```

在隔离Wine中显式设置：

- LWMEDIA_SNAPSHOT_PATH：该bin文件的Wine可读Windows路径。
- LWMEDIA_ALLOW_FIXTURE=1：否则PE拒绝fixture。
- LWMEDIA_TRACE=1：仅方法名/HRESULT。

运行lwmedia-contract-probe.exe <bridge.dll> [--watch-ms 3000]；探针检查基本getter、Genres集合、实际封面ReadAsync、事件注册/移除。watch期间将同一路径重新生成generation2 / phaseB可检查metadata回调；--absent可检查session移除。所有这些仅是合成契约测试。

fixture broker可使用 `broker.py --fixture ... --output ... --watch --commands-dir <private0700dir>` 测试拒绝控制请求；不会调用播放器或生成假成功。

## 真实native transport集成点（用户确认后）

Native supervisor管理helper/broker生命周期；只有选择来源并完成授权后启动broker live模式。参数必须包含 --player、--helper、--allow-automation、--output；需要控制时显式加 --commands-dir，PE用LWMEDIA_COMMAND_DIR指向同一个私有目录。需要Spotify封面bytes时加 --fetch-artwork，URL仅接受HTTPS并限制16MiB；不下载时Thumbnail为空，URL不会伪装成图片。

Live快照无需LWMEDIA_ALLOW_FIXTURE。先用契约探针验证真实数据，再仅在隔离prefix注册该DLL的DllPath，开启原版mediaintegration，验证曲名/封面/暂停/seek/切歌/退出/权限拒绝/生命周期；最后与Windows基线对照。保留原EXE、Steam DLL和作者包原字节。

## 主线程实际 Wine11 契约结果（2026-10-15）

主线程已在独立 prefix 运行冻结 checkpoint-1。记录 `build/media-bridge/contract-state/contract-events.log` 显示：title 为明确合成的 Fixture media A；Genres 标准空集合成功；Thumbnail 的 OpenReadAsync / ReadAsync 成功读取32字节；30秒观察窗口内 A→B 后回调1次，事件注册和移除均成功。记录及日志 SHA256 见 `build/media-bridge/validation-parent-contracts.json`。这只证明该探针覆盖的 Wine ABI 契约，不代表实际媒体、原版引擎消费者或 Windows 表现已通过。

## 原版引擎消费者：独立 fixture 测试步骤（尚未执行）

静态定位结果在 `build/media-bridge/consumer-static-evidence.json`。真实 WinRT 激活调用在原版 `bin/winrtutil64.exe`，其中 ManagerStatics IID 位于文件偏移3443448，类名UTF-16位于3446016；32位helper也存在。UI脚本只暴露SceneScript的五类media事件，不直接调用WinRT。未出现其余IID字节不能推论接口未被使用，C++/WinRT可直接调用默认接口vtable。实际覆盖须看原消费者trace，不能以探针替代。

以下均由主线程/操作者显式执行，`prepare`仅文件操作，另外几个命令会运行Wine。先停止**作为复制来源的契约prefix**，再声明 `--source-prefix-stopped`；此参数是操作者前提声明，脚本不能证明来源没有活动进程。不要复制正在使用的prefix。

```sh
PY=/opt/homebrew/bin/python3.13
TEST=playback/media_bridge/tests/engine_fixture.py
STATE=build/media-bridge/engine-fixture-1
$PY "$TEST" prepare --state "$STATE" --runtime build/runtime11 \
  --source-prefix build/media-bridge/contract-state/prefix --source-prefix-stopped \
  --project build/library/3477054430.weproject/project.json \
  --artifacts build/media-bridge/checkpoint-1
$PY "$TEST" register --state "$STATE"
$PY "$TEST" run --state "$STATE" --seconds 60 --width 1470 --height 956
```

`prepare`创建具所有权标记的独立prefix、engine和作者project副本，验证c:指向副本内drive_c；只改副本的mediaintegration/videoaudiooutput。生成的 `register-fixture.reg` 只由显式register步骤导入私有prefix：注册新DLL的类名/DllPath，并将该prefix的Wine Audio驱动设为空，防止启动瞬间发声；不改系统音量。脚本不加载desktop_window_bridge，因此使用唯一标题的普通测试窗口，不占用当前桌面窗口。测试出现无声设备警告须与媒体桥错误分别判断。

run期间可从另一终端更新同一明确合成fixture：

```sh
$PY playback/media_bridge/tests/write_fixture.py --output "$STATE/session.bin" --generation 2 --phase B
# 可选session移除，观察原消费者是否释放事件/封面：
$PY playback/media_bridge/tests/write_fixture.py --output "$STATE/session.bin" --generation 3 --phase B --absent
```

预期证据：`engine-consumer.log`出现 `[LWMedia] DllGetActivationFactory`、`request_facet`及原消费者实际调用；没有类激活失败/c0000409；原Scene显示合成标题/封面并在A→B后变化。记录它实际调用的事件、stream/async方法及HRESULT。若没有任何桥trace，不能算通过，应先查winrtutil进程架构/启动及是否真正开启私有配置。当前DLL仅x64；若实际派生32位helper，需要另编x86 DLL并注册对应32位视图，不能让x64 DLL假冒x86。

run到时/异常/Ctrl-C均在finally执行只针对独立prefix的wineserver -k及单独-w。需要提前退出或最终清理：

```sh
$PY "$TEST" stop --state "$STATE"
$PY "$TEST" verify --state "$STATE"
$PY "$TEST" cleanup --state "$STATE"
```

cleanup再次停止自有prefix、校验原始源文件哈希，删除私有prefix/engine/project/artifacts（含注册），保留fixture、日志和所有权/原始哈希记录。绝不使用全局killall。运行或清理脚本前应审查state路径及生成的注册文件。合成fixture不会启动Music/Spotify或请求Automation；不能把这个测试作为真实媒体测试。

## 原版helper暴露的事件ABI修复（checkpoint-3-delegate）

原版消费者的首次受控fixture测试在`event_current`返回`E_NOINTERFACE`后fail-fast，零媒体输出帧，不能算通过。根因是桥生成TypedEventHandler泛型IID时误用了EventHandler的基础GUID `9de1c535-...`，正确TypedEventHandler应为`9de1c534-...`；见[微软windows-rs的Foundation源码](https://raw.githubusercontent.com/microsoft/windows-rs/master/crates/libs/windows/src/Windows/Foundation/mod.rs)的TypedEventHandler RuntimeType定义。五种修正后的事件IID均与原版winrtutil64.exe实际handler QI所引用GUID逐字节匹配，偏移记录在`build/media-bridge/delegate-iid-fix-validation.json`。

此前自建探针从桥同一生成文件取得handler IID，形成共同错误，因此事件测试通过不能证明此ABI正确。现在探针使用独立Windows标准IID字面量，新增离线回归断言五种delegate IID，13项离线测试通过。新冻结DLL与探针在`build/media-bridge/checkpoint-3-delegate/`，原checkpoint-1和checkpoint-2-helper保留原样。

`LWMEDIA_TRACE=1`现在另外记录`Handler.QueryInterface`、`RoGetAgileReference`和`Bridge.QueryInterface`的真实requested IID及HRESULT（无对象地址、参数、曲名或路径）。注册依然要求typed QI与真实RoGetAgileReference成功；错误原样返回，没有跳过事件或绕过跨线程规则。此代理仅编译及静态验证，修正后的原版helper运行仍须主线程重试。优先先跑新探针30秒A→B，再让相同原版helper宿主读取A/B。

## DataReader：原消费者封面读取链（当前checkpoint-5-datareader）

原helper在事件IID修复后不再崩溃，父代理记录事件订阅和Invoke成功、两帧状态/timeline，但`Windows.Storage.Streams.DataReader`激活失败使metadata/封面没有输出。Wine11官方`windows.storage/classes.idl`仅注册RandomAccessStreamReference，`streams.c`与`main.c`无DataReader实现，不能仅把类名注册到现有windows.storage.dll解决；留存源码在`build/media-investigation/datareader/`。

新增独立DataReader激活类，与媒体Manager共同指向新桥DLL；没有替换Wine系统DLL。按照[微软Streams ABI源码](https://raw.githubusercontent.com/microsoft/windows-rs/master/crates/libs/windows/src/Windows/Storage/Streams/mod.rs)实现IDataReaderFactory、IDataReaderStatics.FromBuffer、完整26槽IDataReader以及IClosable。LoadAsync后台通过真实IInputStream.ReadAsync和IBuffer读入数据，返回标准IAsyncOperation<UINT32>的实际字节数；ReadBytes消耗已加载真实bytes，没有伪造PNG/元数据或跳过封面。最多16MiB，与现有封面transport限制一致；外部InputStream异步操作超过5秒会返回超时。ByteOrder默认BigEndian；按[官方DataReader并发约束](https://learn.microsoft.com/en-us/uwp/api/windows.storage.streams.datareader)在读取期间并发read/load/detach返回ERROR_INVALID_OPERATION。

新冻结产物在`build/media-bridge/checkpoint-5-datareader/`（checkpoint-4为此前主链初版，保持冻结）。自建探针新增独立微软Factory/Statics IID和方法槽：FromBuffer校验默认BigEndian、切换LittleEndian的UInt32、UTF16LE字符串、Close后RO_E_CLOSED；实际Thumbnail rewind到0后LoadAsync32，ReadBytes结果与之前IInputStream读到的32字节逐字节比较，并检查剩余0和越界错误。预期输出`datareader_endian_utf16_close=true`、`datareader_real_bytes=true bytes=32 unconsumed=0`。14项离线测试与编译通过，**此代理未运行新PE，实际执行结果待父代理记录**。

仅生成审查用注册文件（不会导入）：

```sh
/opt/homebrew/bin/python3.13 build/media-bridge/checkpoint-5-datareader/tests/write_registration.py \
  --dll <私有目录/lwmedia-winrt.dll> --output <私有目录/fixture.reg> --mute-fixture-prefix
```

父代理只在既有独立contract-prefix导入；文件同时注册Manager与DataReader并关闭该prefix音频。先新探针，后原版helper；原helper应以initial absent启动，待manager事件注册后再切present A→B，才能真正进入原版读取session/metadata/cover路径。宿主保持只读且不启动native broker或AppleEvents。输出帧、真实接口trace和完整Scene画面分别验证；DataReader的数字/字符串/Guid/detach等方法仍未与真实Windows系统逐项对照，不能称Windows全功能一致。

## 驻留封面同步完成：checkpoint-6-resident

主线程实际checkpoint-4探针通过DataReader真实32bytes，但原版helper仍只有type3/4帧，metadata/封面分支在ReadBuffer越界。定点反汇编证实原版`0x140046fb9`调用LoadAsync(slot29)，`0x140046feb`只Release返回operation，不查Status/Completed/GetResults，随后`0x140047023`立即调用同count的ReadBuffer(slot15)。证据位于`build/media-investigation/datareader/resident-load/original-load-readbuffer.asm`。原版实际依赖内存输入的LoadAsync立即完成。

checkpoint-6只对本DLL精确`vt_input`的驻留Blob输入，内联运行真实IInputStream.ReadAsync、GetResults和数据提交，再返回已完成operation；没有填充虚构bytes，也没有将任意外部流假称已完成。未知外部或proxy vtable继续后台异步。输入支持INoMarshal与否没有被更改：trace中的`ecc8691b-c1db-4dc0-855e-65f6c551af49`是SDK的INoMarshal，不是缺失DataReader接口；这里E_NOINTERFACE后IAgileObject/RoGetAgileReference已成功，不能注册假的INoMarshal。

新探针除既有检查外，按原版形态直接丢弃LoadAsync operation、立即ReadBuffer并比较真实32bytes（预期`datareader_original_consumer_inline_readbuffer=true`）。还以独立agile转发InputStream gate延迟真实原InputStream，检查加载中读错误以及放开gate后实际bytes的异步完成（预期`datareader_foreign_async_real_bytes=true`），防止误将所有外部输入改为同步。仅编译与14项离线检查完成；上述两个PE回归和原版helpermetadata/cover仍须主线程实际运行。冻结包4/5保持不变。

## 实际原版消费者已通过的范围（2026-10-15，checkpoint-6）

主线程已实际运行Wine11：新探针四个DataReader回归全true；原版winrtutil64读取absent→A→B后输出8帧，type1/2/3/4各2。独立检查保留frames：A/B标题正确，metadata有**8个**字符串（末尾bundle ID，此前7字段注释遗漏source），中间字段保持未命名；两个98bytes PNG完整CRC有效且内容不同；播放wire状态1→2、进度10→40/总240秒。原helper原字节hash不变。可复核证据与hash在`build/media-bridge/validation-parent-original-consumer-resident.json`。

这证明原版Windows媒体helper能够消费桥提供的真实字节/事件协议；输入仍是明确合成fixture。真实Music/Spotify只读数据、首次Automation身份与授权、完整屋顶猫Scene显示、控制命令、全部播放器枚举及Windows表现一致性仍未通过。正常runtime媒体桥未默认接入。当前用户尚未回答新增Music/Spotify只读Automation授权问题，未据此发任何AppleEvents。

## 初始已存在session：应补原引擎只读初始化（checkpoint-7-startup）

进一步定点追踪纠正了早先判断：原引擎实际会在启动helper后发送type6的mediablocklist JSON配置，helper处理后主动GetCurrentSession并订阅选定来源。因此最小宿主此前遗漏了原生启动协议，不能把它直接称为桥的Windows事件语义缺陷，更不应伪造CurrentSessionChanged或用户换歌。

原引擎`0x1400c8d7c`启动helper后，`0x1400c8dc8`写type6，`0x1400c8e31`发送保存blocklist；配置更新`0x1400c88c0`也发送type6。helper type6分支`0x140045fe8`解析配置后，`0x140046805`调用刷新选择，`0x140035edb`调用Manager.GetCurrentSession(slot6)；该链仅getter/选择/订阅，没有媒体播放控制。证据在`build/media-investigation/helper-protocol/engine-helper-start.asm`、`engine-blocklist-update.asm`、`input-callback.asm`和`helper-refresh-selection.asm`。

新宿主默认依然仅捕获输出；显式`--initialize-readonly`只发送一次固定type6/完整帧/JSON `[]`，清空fixture helper的来源blocklist并触发只读发现。不提供任意消息/控制payload入口。真实完整engine已有自己的初始化路径和实际blocklist，不应由测试宿主覆盖用户配置。重启新helper时由原engine或测试宿主再发送一次初始化，之后只靠实际session/metadata变化；不周期性重放配置来制造事件。

新冻结包`build/media-bridge/checkpoint-7-startup/`复用checkpoint-6已验证DLL**相同字节/hash**，未改WinRT语义。新probe明确输出`current_session_available_before_event_subscription=true`，独立验证GetCurrentSession在订阅前可读已有session。新runner由主线程显式执行，使用专属contract-prefix、私有双类注册和音频关闭，始终finally停止该prefix：

```sh
PY=/opt/homebrew/bin/python3.13
ART=build/media-bridge/checkpoint-7-startup
$PY "$ART/tests/run_helper_startup.py" --runtime build/runtime11 \
  --prefix build/media-bridge/contract-state/prefix \
  --helper build/media-bridge/helper-consumer-1/winrtutil64.exe \
  --artifacts "$ART" --out build/media-bridge/startup-present-1 --mode present
$PY "$ART/tests/run_helper_startup.py" --runtime build/runtime11 \
  --prefix build/media-bridge/contract-state/prefix \
  --helper build/media-bridge/helper-consumer-1/winrtutil64.exe \
  --artifacts "$ART" --out build/media-bridge/startup-transitions-1 --mode transitions
```

present模式在helper启动前已发布A，全程不改snapshot，预期只出现一次A、只读初始化一次、没有Event.Invoke重复。transitions模式initial absent，订阅后A，4秒后B，预期A/B各一次。runner记录原helper前后hash、实际帧和判断，任何缺帧/重复均失败。此代理只编译、脚本语法检查和14项离线检查，未执行这些新Wine回归；等待主线程实际结果。冻结包6保持不变。

生命周期复审见`build/media-bridge/final-lifecycle-review.md`。实际host仍曾使用owned_child_timeout_terminate，不能把host_exit0说成helper优雅退出；session移除/来源切换、取消/晚完成、非agile STA回调与完整Windows行为仍需分别验证。
