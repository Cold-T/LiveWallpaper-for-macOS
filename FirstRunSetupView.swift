import SwiftUI
import AppKit

struct FirstRunSetupView: View {
    let onComplete: () -> Void
    @State private var step = 0
    @State private var busy = false
    @State private var started = false
    @State private var progress = 0.0
    @State private var status = ""
    @State private var failure = ""
    @State private var selectedPath = ""
    private var bundledEnginePath: String? {
        Bundle.main.url(forResource: "WallpaperEngine", withExtension: nil)?.path
    }
    private var chinese: Bool {
        let language = UserDefaults.standard.string(forKey: "app_language") ?? "auto"
        return (language == "auto" ? Locale.preferredLanguages.first ?? "en" : language).hasPrefix("zh")
    }
    private func text(_ zh: String, _ en: String) -> String { chinese ? zh : en }
    private var titles: [String] {
        [text("准备播放组件", "Install playback components"), text("导入 Wallpaper Engine", "Import Wallpaper Engine"),
         text("配置播放环境", "Configure playback environment"), text("开始使用", "Ready to go")]
    }
    private var installationDescription: String {
        switch step {
        case 0:
            return text("自动准备固定版本 Wine、DXMT 和媒体组件。公开安装版会从官方来源下载，请保持联网；无需额外开发工具。",
                        "Preparing pinned Wine, DXMT and media components. The public setup edition downloads from official sources; keep your internet connection available. No developer tools are needed.")
        case 1:
            return text("正在校验并导入引擎组件，请稍候。", "Verifying and importing engine components.")
        default:
            return text("正在建立独立环境并配置字体和显示器，请稍候。",
                        "Creating an isolated environment and configuring fonts and displays.")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(text("欢迎使用 Livewallpaper for macOS", "Welcome to Livewallpaper for macOS"))
                    .font(.title2.bold())
                Text(text("只需配置一次，之后直接进入壁纸管理。", "Set up once, then open straight into your wallpaper library."))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                ForEach(0..<4) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: index < step ? "checkmark.circle.fill" : "\(index + 1).circle.fill")
                            .font(.title2).foregroundStyle(index <= step ? Color.accentColor : Color.secondary)
                        Text(titles[index]).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider()
            if step == 1 && !busy && bundledEnginePath == nil {
                Text(text("选择你安装的 Wallpaper Engine 文件夹或 wallpaper64.exe。", "Select your Wallpaper Engine installation folder or wallpaper64.exe."))
                Text(text("当前适配版本：2.8.42。应用会复制并核对所需组件，不会修改原始文件。", "Supported version: 2.8.42. Required components are copied and verified; your originals stay untouched."))
                    .font(.callout).foregroundStyle(.secondary)
                if !selectedPath.isEmpty { Text(selectedPath).font(.caption).lineLimit(2).textSelection(.enabled) }
            } else if step == 3 {
                Label(text("播放环境已准备就绪", "Your playback environment is ready"), systemImage: "checkmark.seal.fill")
                    .font(.title3).foregroundStyle(.green)
                Text(text("现在可以下载、管理和播放壁纸。音量可从工具栏或菜单栏调节。", "You can now download, manage and play wallpapers. Adjust volume from the toolbar or menu bar."))
            } else {
                Text(installationDescription)
            }
            if busy {
                ProgressView(value: progress).accessibilityLabel(text("安装进度", "Setup progress"))
                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            if !failure.isEmpty {
                ScrollView { Text(failure).font(.callout).foregroundStyle(.red).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 100)
            }
            Spacer(minLength: 0)
            HStack {
                if busy { Text(text("安装中，请保持应用打开。", "Keep the app open while setup runs.")).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if step == 3 {
                    Button(text("进入壁纸管理", "Open wallpaper library"), action: onComplete).buttonStyle(.borderedProminent)
                } else if !busy {
                    if step == 0 { Button(text("重试", "Retry"), action: prepare).buttonStyle(.borderedProminent) }
                    else if let bundledEnginePath {
                        Button(text("重试", "Retry")) { importEngine(bundledEnginePath) }.buttonStyle(.borderedProminent)
                    } else { Button(text("选择 Wallpaper Engine…", "Choose Wallpaper Engine…"), action: chooseEngine).buttonStyle(.borderedProminent) }
                }
            }
        }
        .padding(32)
        .frame(minWidth: 680, minHeight: 480)
        .onAppear { if !started { started = true; prepare() } }
    }
    private func prepare() {
        busy = true; failure = ""; step = 0; progress = 0
        LWSetupPrepareComponents({ message, value in status = message ?? ""; progress = max(progress, value) }, { error in
            busy = false
            if let error { failure = error }
            else {
                step = 1; progress = 0.25
                if let bundledEnginePath { importEngine(bundledEnginePath) }
            }
        })
    }
    private func chooseEngine() {
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true; picker.canChooseFiles = true; picker.allowsMultipleSelection = false
        picker.title = text("选择 Wallpaper Engine 2.8.42", "Select Wallpaper Engine 2.8.42")
        guard picker.runModal() == .OK, let url = picker.url else { return }
        importEngine(url.path)
    }
    private func importEngine(_ path: String) {
        selectedPath = path; failure = ""; busy = true; step = 1; progress = 0.25
        let screens: [[String: Any]] = NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(id.uint32Value)?.takeRetainedValue() else { return nil }
            return ["uuid": CFUUIDCreateString(nil, uuid)! as String, "retina": screen.backingScaleFactor >= 1.5]
        }
        LWSetupImportEngine(selectedPath, screens, { message, value in status = message ?? ""; progress = max(progress, value); if value >= 0.65 { step = 2 } }, { runtime, error in
            busy = false
            if runtime != nil { step = 3; progress = 1 }
            else { step = 1; failure = error ?? text("配置失败，请重试。", "Setup failed. Please retry.") }
        })
    }
}
