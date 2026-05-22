/*
 * This file is part of LiveWallpaper – LiveWallpaper App for macOS.
 * Copyright (C) 2025 Bios thusvill
 * Copyright (C) 2026 Cold-T
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import AVFoundation
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Compatibility Bridge
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

extension View {
    @ViewBuilder
    func compatibleGlass(
        material: NSVisualEffectView.Material = .headerView, cornerRadius: CGFloat = 16
    ) -> some View {
        if #available(macOS 20.0, *) {
            self.background(
                VisualEffectView(material: material)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            )
        } else {
            self.background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

// MARK: - String Localization Extension
enum AppLocalization {
    nonisolated static func localizedString(
        _ key: String,
        languageOverride: String? = nil
    ) -> String {
        let selectedLanguage =
            languageOverride
            ?? UserDefaults.standard.string(forKey: "app_language")
            ?? "auto"
        let language =
            selectedLanguage == "auto"
            ? Locale.preferredLanguages.first ?? "en"
            : selectedLanguage

        for candidate in languageCandidates(for: language) {
            if let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return NSLocalizedString(key, tableName: nil, bundle: bundle, comment: "")
            }
        }

        return NSLocalizedString(key, comment: "")
    }

    nonisolated private static func languageCandidates(for language: String) -> [String] {
        let parts = language.split(separator: "-").map(String.init)
        var candidates = [language]

        if parts.count >= 2 {
            candidates.append(parts.prefix(2).joined(separator: "-"))
        }
        if let baseLanguage = parts.first {
            candidates.append(baseLanguage)
        }
        candidates.append("en")

        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }
}

extension String {
    nonisolated var localized: String {
        AppLocalization.localizedString(self)
    }
}

// MARK: - Language Manager
class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published var currentLanguage: String {
        didSet {
            UserDefaults.standard.set(currentLanguage, forKey: UserDefaultsKeys.appLanguage)
            if currentLanguage == "auto" {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([currentLanguage], forKey: "AppleLanguages")
            }
            UserDefaults.standard.synchronize()
        }
    }

    var availableLanguages: [(code: String, name: String)] {
        [
            ("auto", localizedString("system_language")),
            ("zh-Hans", "简体中文"),
            ("en", "English"),
        ]
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: UserDefaultsKeys.appLanguage) ?? "auto"
        self.currentLanguage = saved
    }

    func localizedString(_ key: String) -> String {
        AppLocalization.localizedString(key, languageOverride: currentLanguage)
    }
}

// MARK: - Localization
enum L {
    private static func tr(_ key: String) -> String {
        LanguageManager.shared.localizedString(key)
    }

    static var selectWallpaperFolder: String { tr("select_wallpaper_folder") }
    static var generating: String { tr("generating") }
    static var settings: String { tr("settings") }
    static var wallpaperFolder: String { tr("wallpaper_folder") }
    static var selectFolderEmoji: String { tr("select_folder_emoji") }
    static var showInFinder: String { tr("show_in_finder") }
    static var videoScalingMode: String { tr("video_scaling_mode") }
    static var scaleFill: String { tr("scale_fill") }
    static var scaleFit: String { tr("scale_fit") }
    static var scaleStretch: String { tr("scale_stretch") }
    static var scaleCenter: String { tr("scale_center") }
    static var scaleHeightFill: String { tr("scale_height_fill") }
    static var randomOnStartup: String { tr("random_on_startup") }
    static var randomOnLid: String { tr("random_on_lid") }
    static var pauseWhenActive: String { tr("pause_when_active") }
    static var videoVolume: String { tr("video_volume") }
    static var optimizeCodecs: String { tr("optimize_codecs") }
    static var optimize: String { tr("optimize") }
    static var clearCache: String { tr("clear_cache") }
    static var clearCacheButton: String { tr("clear_cache_button") }
    static var resetUserData: String { tr("reset_userdata") }
    static var reset: String { tr("reset") }
    static var selectFolderTitle: String { tr("select_folder_title") }
    static var choose: String { tr("choose") }
    static var selectFolderOrType: String { tr("select_folder_or_type") }
    static var wallpaperRotation: String { tr("wallpaper_rotation") }
    static var rotationType: String { tr("wallpaper_rotation_type") }
    static var vinttageBar: String { tr("vignette_bar") }
    static var rotationDelay: String { tr("wallpaper_rotation_delay") }
    static var appLanguage: String { tr("app_language") }
    static var systemLanguage: String { tr("system_language") }
    static var steamWorkshop: String { tr("Steam Workshop") }
    static var workshopPlaceholder: String { tr("Workshop URL or ID") }
    static var importWorkshop: String { tr("Import") }
    static var importingWorkshop: String { tr("Importing...") }
    static var workshopImported: String { tr("Workshop item imported") }
    static var steamUsername: String { tr("Steam username") }
    static var steamPassword: String { tr("Steam password") }
    static var steamLogin: String { tr("Login") }
    static var steamCheck: String { tr("Check") }
    static var checkingSteamLogin: String { tr("Checking Steam login...") }
    static var steamLoggedIn: String { tr("Steam login is valid") }
    static var steamLoginRequired: String { tr("Steam login is required") }
    static var stopWallpaper: String { tr("Stop wallpaper") }
    static var openingSteamLogin: String { tr("Opening Terminal...") }
    static var steamLoginTerminalOpened: String { tr("Steam login terminal opened") }
}

// MARK: - UserDefaults Keys
enum UserDefaultsKeys {
    static let wallpaperFolder = "WallpaperFolder"
    static let scaleMode = "scale_mode"
    static let randomOnStartup = "random"
    static let randomOnLid = "random_lid"
    static let pauseOnAppFocus = "pauseOnAppFocus"
    static let volumePercentage = "wallpapervolumeprecentage"
    static let launchAtLogin = "LaunchAtLogin"
    static let appLanguage = "app_language"
    static let vignetteBar = "vinttage_bar"
    static let rotation = "rotation"
    static let rdelay = "rdelay"
    static let rtype = "rtype"
    static let steamUsername = "steam_username"

}

extension Notification.Name {
    static let liveWallpaperShouldRefresh = Notification.Name("LiveWallpaperShouldRefresh")
}

// MARK: - Main Content View
struct ContentView: View {
    @StateObject private var viewModel = WallpaperViewModel()
    @StateObject private var languageManager = LanguageManager.shared
    @State private var showSettings = false
    @StateObject private var displayManager = DisplayManager()

    var body: some View {

        ZStack {

            VStack(spacing: 0) {
                Spacer(minLength: 20)
                ToolbarView(
                    showSettings: $showSettings,
                    onReload: { viewModel.reloadContent() },
                    onStopWallpaper: { viewModel.stopWallpaper() }
                )
                    .padding(.horizontal).padding(.top, 24).padding(.bottom, 12)

                ZStack(alignment: .bottom) {
                    VideoGridView(
                        videos: viewModel.videos, viewModel: viewModel,
                        onVideoSelect: { video in
                            viewModel.startWallpaper(
                                video: video, displays: Array(displayManager.selectedDisplays))
                        }
                    )
                    .padding(.horizontal, 24).padding(.bottom, 24)

                    DisplayDockView(
                        displays: displayManager.displays,
                        selectedDisplays: $displayManager.selectedDisplays
                    )
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            .ignoresSafeArea(.all)
            .compatibleGlass(cornerRadius: 16)
            .frame(minWidth: 600, minHeight: 250)
            //.sheet(isPresented: $showSettings) { SettingsView(viewModel: viewModel) }
            .onAppear {
                refreshContent()
            }
            .onReceive(NotificationCenter.default.publisher(for: .liveWallpaperShouldRefresh)) { _ in
                refreshContent()
            }

            if showSettings {

                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showSettings = false

                    }

                SettingsView(viewModel: viewModel)
                    .shadow(radius: 3)
                    .cornerRadius(15)
                    .onTapGesture {}
                    .animation(.easeInOut, value: showSettings)
            }

        }.animation(.easeInOut, value: showSettings)
    }

    private func refreshContent() {
        viewModel.loadDisplays()
        viewModel.reloadContent()
        viewModel.checkSteamLoginStatus()
    }
}

// MARK: - Toolbar View
struct ToolbarView: View {
    @Binding var showSettings: Bool
    let onReload: () -> Void
    let onStopWallpaper: () -> Void

    var body: some View {
        HStack {
            Spacer()

            if #available(macOS 26.0, *) {
                Button(action: onReload) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16))
                }
                .buttonStyle(.glass)
            } else {
                Button(action: onReload) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16))
                }
            }

            if #available(macOS 26.0, *) {
                Button(action: onStopWallpaper) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 16))
                }
                .buttonStyle(.glass)
                .help(L.stopWallpaper)
            } else {
                Button(action: onStopWallpaper) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 16))
                }
                .help(L.stopWallpaper)
            }

            if #available(macOS 26.0, *) {
                Button(action: { showSettings = true }) {
                    Image(systemName: "gear")
                        .font(.system(size: 16))
                }
                .buttonStyle(.glass)
            } else {
                Button(action: { showSettings = true }) {
                    Image(systemName: "gear")
                        .font(.system(size: 16))
                }
            }
        }
    }
}

struct SteamLoginStatusBadge: View {
    let status: SteamLoginStatus

    var body: some View {
        Group {
            switch status {
            case .idle:
                EmptyView()
            case .checking:
                ProgressView()
                    .controlSize(.small)
            case .loggedIn(_), .loginRequired:
                Text(status.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.foregroundStyle)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(status.backgroundStyle, in: Capsule())
                    .lineLimit(1)
            }
        }
    }
}

enum SteamLoginStatus {
    case idle
    case checking
    case loggedIn(String)
    case loginRequired

    var label: String {
        switch self {
        case .idle, .checking:
            ""
        case .loggedIn(let username):
            username.isEmpty ? L.steamLoggedIn : "\(L.steamLoggedIn): \(username)"
        case .loginRequired:
            L.steamLogin
        }
    }

    var foregroundStyle: Color {
        switch self {
        case .idle, .checking:
            .secondary
        case .loggedIn(_):
            .green
        case .loginRequired:
            .red
        }
    }

    var backgroundStyle: Color {
        foregroundStyle.opacity(0.12)
    }

    var isLoggedIn: Bool {
        if case .loggedIn(_) = self {
            return true
        }
        return false
    }

    var isChecking: Bool {
        if case .checking = self {
            return true
        }
        return false
    }
}

// MARK: - Video Grid View
struct VideoGridView: View {
    let videos: [VideoItem]
    let viewModel: WallpaperViewModel
    let onVideoSelect: (VideoItem) -> Void

    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 250), spacing: 2)]

    var body: some View {
        ScrollView {
            if videos.isEmpty {
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.title = L.selectFolderTitle
                    panel.prompt = L.choose

                    if panel.runModal() == .OK, let url = panel.url {
                        viewModel.folderPath = url.path
                        sharedEngine?.selectFolder(url.path())
                        viewModel.reloadContent()
                    }
                } label: {
                    Text(L.selectWallpaperFolder)
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(videos) { video in
                        VideoThumbnailButton(video: video) {
                            onVideoSelect(video)
                        }
                        .id(video.id)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
        }
    }
}

// MARK: - Video Thumbnail Button
struct VideoThumbnailButton: View {
    let video: VideoItem
    let action: () -> Void
    @ObservedObject private var cache = ThumbnailCache.shared

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                let _ = cache.lastUpdate

                if let thumbnail = video.loadThumbnail() {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(16 / 9, contentMode: .fill)
                        .frame(height: 140)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 140)
                        .overlay {
                            VStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text(L.generating)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                }

                if let quality = video.quality, !quality.isEmpty {
                    QualityBadge(text: quality)
                        .padding(8)
                }
            }
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .padding(2)
        .help(video.filename)
    }
}

// MARK: - Quality Badge
struct QualityBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.black, lineWidth: 1)
            )
    }
}

// MARK: - Display Manager
class DisplayManager: ObservableObject {
    @Published var displays: [DisplayObjc] = []
    @Published var selectedDisplays: Set<UInt32> = []

    init() {
        sharedEngine?.scanDisplays()
        updateDisplays()
        CGDisplayRegisterReconfigurationCallback(
            displayReconfigCallback, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit {
        CGDisplayRemoveReconfigurationCallback(
            displayReconfigCallback, Unmanaged.passUnretained(self).toOpaque())
    }

    func updateDisplays() {
        sharedEngine?.scanDisplays()
        DispatchQueue.main.async { [weak self] in
            self?.displays = sharedEngine?.getDisplays() as? [DisplayObjc] ?? []
        }
    }
}

nonisolated(unsafe) private let displayReconfigCallback: CGDisplayReconfigurationCallBack = {
    display, flags, userInfo in
    guard let userInfo = userInfo else { return }
    let manager = Unmanaged<DisplayManager>.fromOpaque(userInfo).takeUnretainedValue()
    DispatchQueue.main.async {
        manager.updateDisplays()
        manager.selectedDisplays.removeAll()
    }
}

// MARK: - Display Dock View
struct DisplayDockView: View {
    let displays: [DisplayObjc]
    @Binding var selectedDisplays: Set<UInt32>
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 10) {
            ForEach(displays, id: \.screen) { display in
                DisplayButton(
                    display: display,
                    isSelected: selectedDisplays.contains(display.screen)
                ) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        if selectedDisplays.contains(display.screen) {
                            selectedDisplays.remove(display.screen)
                        } else {
                            selectedDisplays.insert(display.screen)
                        }
                    }
                }
                .matchedGeometryEffect(id: display.screen, in: namespace)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: displays.map { $0.screen })
    }
}

// MARK: - Display Button
struct DisplayButton: View {
    let display: DisplayObjc
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Spacer()
                Text(display.getDisplayName()).font(.system(size: 12, weight: .bold)).lineLimit(1)
                Text(display.getResolution()).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(width: 200, height: 80)
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
            .background {
                if #available(macOS 26.0, *) {
                    Color.clear.glassEffect(
                        .regular.interactive(), in: .rect(cornerRadius: isSelected ? 26 : 20))
                } else {
                    VisualEffectView(material: isSelected ? .selection : .headerView)
                        .clipShape(RoundedRectangle(cornerRadius: isSelected ? 26 : 20))
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(
                        Color.yellow, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .shadow(
            color: isSelected ? Color.yellow.opacity(0.45) : Color.black.opacity(0.15),
            radius: isSelected ? 20 : 10, y: 8
        )
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: isSelected)
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @ObservedObject private var languageManager = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showFolderPicker = false
    @State private var workshopInput = ""
    @State private var workshopStatus = ""
    @State private var workshopStatusIsError = false
    @State private var steamLoginStatus = ""
    @State private var steamPassword = ""
    @State private var isImportingWorkshop = false
    @State private var importProgress = 0.0
    @State private var importProgressTask: Task<Void, Never>?
    @AppStorage(UserDefaultsKeys.steamUsername) var steamUsername = ""
    @AppStorage(UserDefaultsKeys.scaleMode) var scaleMode: Int = 0
    @State private var localMinutes: Int = 60
    @State private var isShowingView = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header
            HStack {
                Text(L.settings)
                    .font(.title2)
                    .fontWeight(.bold)

            }
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Folder Selection
                    SettingRow(title: L.wallpaperFolder) {
                        HStack {
                            TextField(L.selectFolderOrType, text: $viewModel.folderPath)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                            Button(action: selectFolder) {
                                //Image(systemName: "folder.fill")
                                Image("openfolder").resizable().frame(width: 23, height: 23)
                            }
                            Button(action: openInFinder) {
                                Image("folder").resizable().frame(width: 23, height: 23)
                            }
                            
                            
                        }
                    }

                    Divider()

	                    SettingRow(title: L.steamWorkshop) {
	                        VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .center, spacing: 8) {
                                    SteamLoginStatusBadge(
                                        status: viewModel.steamLoginStatus
                                    )
                                    .frame(width: 230, alignment: .leading)

                                    Button(L.steamCheck) {
                                        viewModel.checkSteamLoginStatus()
                                    }
                                    .frame(width: 96, height: 24)
                                    .disabled(
                                        steamUsername.trimmingCharacters(
                                            in: .whitespacesAndNewlines
                                        ).isEmpty || viewModel.steamLoginStatus.isChecking
                                    )
                                }

	                            HStack(alignment: .center, spacing: 8) {
		                            VStack(alignment: .leading, spacing: 6) {
	                                    TextField(L.steamUsername, text: $steamUsername)
	                                        .textFieldStyle(.roundedBorder)
	                                        .frame(width: 230)
                                            .onChange(of: steamUsername) { _, _ in
                                                viewModel.resetSteamLoginStatus()
                                            }

		                                SecureField(L.steamPassword, text: $steamPassword)
		                                    .textFieldStyle(.roundedBorder)
		                                    .frame(width: 230)
		                            }

	                                Button(L.steamLogin) {
	                                    openSteamLoginTerminal()
	                                }
	                                .frame(width: 96, height: 52)
	                                .disabled(
	                                    steamUsername.trimmingCharacters(
	                                        in: .whitespacesAndNewlines
	                                    ).isEmpty || steamPassword.isEmpty
	                                )
		                        }

                            HStack {
                                TextField(L.workshopPlaceholder, text: $workshopInput)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 230)

                                Button {
                                    importWorkshopItem()
                                } label: {
                                    Text(isImportingWorkshop ? L.importingWorkshop : L.importWorkshop)
                                }
                                .frame(width: 96, height: 24)
                                .disabled(
                                    isImportingWorkshop
                                        || workshopInput.trimmingCharacters(
                                            in: .whitespacesAndNewlines
                                        ).isEmpty
                                        || !viewModel.steamLoginStatus.isLoggedIn
                                )
                            }

                            if isImportingWorkshop {
                                ProgressView(value: importProgress, total: 1.0)
                                    .progressViewStyle(.linear)
                                    .frame(width: 334)
                            }

                            if !workshopStatus.isEmpty {
                                Text(workshopStatus)
                                    .font(.caption)
                                    .foregroundStyle(workshopStatusIsError ? .red : .secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(width: 334, alignment: .leading)
                            }

                            if !steamLoginStatus.isEmpty {
                                Text(steamLoginStatus)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(width: 334, alignment: .leading)
                            }
                        }
                    }

                    Divider()

                    // Scale Mode
                    SettingRow(title: L.videoScalingMode) {

                        Picker("", selection: $scaleMode) {
                            Text(L.scaleFill).tag(0)
                            Text(L.scaleFit).tag(1)
                            Text(L.scaleStretch).tag(2)
                            Text(L.scaleCenter).tag(3)
                            Text(L.scaleHeightFill).tag(4)
                        }
                        .onChange(of: scaleMode) {

                            viewModel.engine.updateScaleMode(scaleMode)
                        }

                    }

                    Divider()

                    // Language Selection
                    SettingRow(title: L.appLanguage) {
                        Picker(
                            "",
                            selection: Binding(
                                get: { languageManager.currentLanguage },
                                set: { newValue in
                                    languageManager.currentLanguage = newValue
                                }
                            )
                        ) {
                            Text(L.systemLanguage).tag("auto")
                            Text("简体中文").tag("zh-Hans")
                            Text("English").tag("en")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 150)
                    }

                    Divider()

                    // Random Wallpaper on Startup
                    SettingRow(title: L.randomOnStartup) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: {
                                    UserDefaults.standard.bool(
                                        forKey: UserDefaultsKeys.randomOnStartup)
                                },
                                set: {
                                    UserDefaults.standard.set(
                                        $0, forKey: UserDefaultsKeys.randomOnStartup)
                                }
                            )
                        )
                        .toggleStyle(.switch)
                    }

                    // Random Wallpaper on Wakeup
                    SettingRow(title: L.randomOnLid) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: {
                                    UserDefaults.standard.bool(forKey: UserDefaultsKeys.randomOnLid)
                                },
                                set: {
                                    UserDefaults.standard.set(
                                        $0, forKey: UserDefaultsKeys.randomOnLid)
                                }
                            )
                        )
                        .toggleStyle(.switch)
                    }

                    // Auto-Pause When App is Active
                    SettingRow(title: L.pauseWhenActive) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: {
                                    UserDefaults.standard.bool(
                                        forKey: UserDefaultsKeys.pauseOnAppFocus)
                                },
                                set: {
                                    UserDefaults.standard.set(
                                        $0, forKey: UserDefaultsKeys.pauseOnAppFocus)
                                }
                            )
                        )
                        .toggleStyle(.switch)
                    }

                    //Vinttage Bar
                    SettingRow(title: L.vinttageBar) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: {
                                    UserDefaults.standard.bool(forKey: UserDefaultsKeys.vignetteBar)
                                },
                                set: {
                                    UserDefaults.standard.set(
                                        $0, forKey: UserDefaultsKeys.vignetteBar)
                                }
                            )
                        )
                        .toggleStyle(.switch)
                    }

                    Divider()

                    SettingRow(title: L.wallpaperRotation) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: {
                                    UserDefaults.standard.bool(forKey: UserDefaultsKeys.rotation)
                                },
                                set: { newValue in
                                    guard let engine = sharedEngine else { return }

                                    engine.isrotationrunning = newValue
                                    if newValue {

                                        engine.startWallpaperRotation()

                                    } else {
                                        engine.stopWallpaperRotation()
                                    }
                                    UserDefaults.standard.set(
                                        newValue, forKey: UserDefaultsKeys.rotation)
                                }
                            )
                        ).toggleStyle(.switch)

                    }

                    SettingRow(title: L.rotationDelay) {
                        HStack(spacing: 8) {
                            // 1. The Typeable Field
                            TextField("", value: $localMinutes, format: .number)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 40)  // Keeps it compact
                                .onSubmit {
                                    // Ensure the typed value stays within your bounds
                                    localMinutes = min(max(localMinutes, 1), 1440)
                                }

                            // 2. The Stepper (with an empty label)
                            Stepper("", value: $localMinutes, in: 1...1440, step: 4)
                                .labelsHidden()  // This hides the extra space Stepper usually takes
                                .onChange(of: localMinutes) { newValue in
                                    sharedEngine?.rotationDelay = Int32(newValue * 60)
                                    UserDefaults.standard.set(
                                        (newValue * 60), forKey: UserDefaultsKeys.rdelay)
                                    print("Delay updated to: \(sharedEngine?.rotationDelay ?? 0)")
                                }

                            // 3. The Formatted Unit
                            Text(formatTime(localMinutes))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize()
                        }

                    }

                    .onAppear {
                        if let engine = sharedEngine {
                            localMinutes =
                                UserDefaults.standard.integer(forKey: UserDefaultsKeys.rdelay) / 60
                        }
                    }

                    if let engine = sharedEngine {
                        SettingRow(title: L.rotationType) {
                            Picker(
                                "",
                                selection: Binding(
                                    get: { engine.rotationType },
                                    set: { newValue in
                                        engine.rotationType = newValue

                                    }
                                )
                            ) {
                                Text("Sequential").tag(RotationType.sequential)
                                Text("Random").tag(RotationType.random)
                            }
                            .onChange(of: engine.rotationType) {
                                if engine.rotationType == RotationType.sequential {
                                    UserDefaults.standard.set(1, forKey: UserDefaultsKeys.rtype)
                                } else {
                                    UserDefaults.standard.set(2, forKey: UserDefaultsKeys.rtype)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 150)
                        }
                    } else {
                        Text("Engine Loading...")  // Or EmptyView()
                    }

                    Divider()

                    // Video Volume
                    SettingRow(title: L.videoVolume) {
                        HStack {
                            Slider(value: $viewModel.volume, in: 0...100, step: 1)
                                .frame(width: 200)
                                .onChange(of: viewModel.volume) { newValue in
                                    sharedEngine?.updateVolume(newValue)
                                }
                            Text("\(Int(viewModel.volume))%")
                                .frame(width: 60, alignment: .leading)
                                .monospacedDigit()
                        }
                    }

                    Divider()

                    // Optimize Videos
                    SettingRow(title: L.optimizeCodecs) {
                        Button(L.optimize) {
                            viewModel.optimizeVideos()
                        }
                        .disabled(true)
                    }

                    // Clear Cache
                    SettingRow(title: L.clearCache) {
                        Button(L.clearCacheButton) {
                            viewModel.clearCache()
                        }
                    }

                    // Reset User Data
                    SettingRow(title: L.resetUserData) {
                        Button(L.reset) {
                            viewModel.resetUserData()
                        }
                    }
                }
                .padding()
            }
        }
        .padding()
        .frame(width: 600, height: 500)
        .background(.ultraThinMaterial)
        .compatibleGlass(cornerRadius: 1)

    }
    func formatTime(_ totalMinutes: Int) -> String {
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(m) min"
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = L.selectFolderTitle
        panel.prompt = L.choose

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.folderPath = url.path
            sharedEngine?.selectFolder(url.path())
            viewModel.reloadContent()
        }
    }

    private func openInFinder() {
        if let url = URL(string: "file://\(viewModel.folderPath)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func importWorkshopItem() {
        isImportingWorkshop = true
        workshopStatusIsError = false
        startImportProgress()
        workshopStatus = L.importingWorkshop

        Task { @MainActor in
            do {
                let output = try await viewModel.importWorkshopItem(workshopInput)
                workshopStatus = output.isEmpty ? L.workshopImported : output
                workshopStatusIsError = false
            } catch {
                workshopStatus = error.localizedDescription
                workshopStatusIsError = true
            }
            finishImportProgress()
            try? await Task.sleep(nanoseconds: 350_000_000)
            isImportingWorkshop = false
            importProgress = 0
        }
    }

    private func startImportProgress() {
        importProgressTask?.cancel()
        importProgress = 0.04
        importProgressTask = Task { @MainActor in
            while !Task.isCancelled && importProgress < 0.92 {
                do {
                    try await Task.sleep(nanoseconds: 180_000_000)
                } catch {
                    return
                }

                let remaining = 0.92 - importProgress
                let step = max(0.006, remaining * 0.07)
                withAnimation(.easeOut(duration: 0.18)) {
                    importProgress = min(0.92, importProgress + step)
                }
            }
        }
    }

    private func finishImportProgress() {
        importProgressTask?.cancel()
        importProgressTask = nil
        withAnimation(.easeOut(duration: 0.2)) {
            importProgress = 1
        }
    }

    private func openSteamLoginTerminal() {
        steamLoginStatus = L.openingSteamLogin

        do {
            try SteamLoginTerminal(username: steamUsername, password: steamPassword).open()
            steamLoginStatus = L.steamLoginTerminalOpened
            viewModel.scheduleSteamLoginStatusChecks()
        } catch {
            steamLoginStatus = error.localizedDescription
        }
    }
}

// MARK: - Setting Row
struct SettingRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(title)
                .frame(width: 200, alignment: .leading)
            content
            Spacer()
        }
    }
}

// MARK: - Video Item
struct VideoItem: Identifiable {
    let id = UUID()
    let filename: String
    let path: String
    let thumbnailPath: String
    var quality: String?

    func loadThumbnail() -> NSImage? {
        return ThumbnailCache.shared.image(for: thumbnailPath)
    }
}

// MARK: - Workshop Import
enum WorkshopImportError: LocalizedError {
    case missingScript
    case failed(status: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .missingScript:
            return "Workshop import script was not found".localized
        case .failed(let status, let output):
            let reason = Self.failureReason(status: status, output: output)
            guard !output.isEmpty else {
                return reason
            }
            return "\(reason)\n\(output)"
        }
    }

    private static func failureReason(status: Int32, output: String) -> String {
        let lowercasedOutput = output.lowercased()

        if status == 2 || lowercasedOutput.contains("could not parse") {
            return "Workshop URL or ID is invalid".localized
        }

        if status == 3 || lowercasedOutput.contains("directory was not found") {
            return "Workshop item was not found".localized
        }

        if status == 4 || lowercasedOutput.contains("no .mp4/.mov") {
            return "Workshop item is not a supported video".localized
        }

        if status == 127 || lowercasedOutput.contains("steamcmd was not found") {
            return "steamcmd was not found".localized
        }

        if lowercasedOutput.contains("network")
            || lowercasedOutput.contains("timeout")
            || lowercasedOutput.contains("connection")
            || lowercasedOutput.contains("failed to connect")
            || lowercasedOutput.contains("download failed") {
            return "Workshop download failed; check network or Steam".localized
        }

        if lowercasedOutput.contains("login failure")
            || lowercasedOutput.contains("password")
            || lowercasedOutput.contains("steam guard")
            || lowercasedOutput.contains("access denied") {
            return "Steam login is required".localized
        }

        return "Workshop import failed".localized
    }
}

struct WorkshopImporter {
    let importFolder: String
    let steamUsername: String?

    func importItem(_ input: String) async throws -> String {
        guard let scriptURL = findScriptURL() else {
            throw WorkshopImportError.missingScript
        }
        let importFolder = importFolder
        let steamUsername = steamUsername?.trimmingCharacters(in: .whitespacesAndNewlines)
        let appBundlePath = Bundle.main.bundlePath

        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            var environment = ProcessInfo.processInfo.environment

            environment["LIVEWALLPAPER_IMPORT_DIR"] = importFolder
            environment["LIVEWALLPAPER_IMPORT_MODE"] = "symlink"
            environment["LIVEWALLPAPER_SKIP_PLAY"] = "1"
            environment["LIVEWALLPAPER_APP"] = appBundlePath
            if let steamUsername, !steamUsername.isEmpty {
                environment["STEAM_USERNAME"] = steamUsername
            }

            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptURL.path, input]
            process.environment = environment
            process.standardOutput = pipe
            process.standardError = pipe

            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let output = String(data: data, encoding: .utf8) ?? ""
            let summary = Self.summary(from: output)

            guard process.terminationStatus == 0 else {
                throw WorkshopImportError.failed(status: process.terminationStatus, output: summary)
            }

            return summary
        }.value
    }

    private func findScriptURL() -> URL? {
        let fileManager = FileManager.default
        let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(
                "tools/download_import_play_workshop_item.sh"),
            Bundle.main.resourceURL?.appendingPathComponent(
                "download_import_play_workshop_item.sh"),
            sourceRoot.appendingPathComponent("tools/download_import_play_workshop_item.sh"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("tools/download_import_play_workshop_item.sh"),
        ].compactMap { $0 }

        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    nonisolated private static func summary(from output: String) -> String {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if let title = lines.last(where: { $0.hasPrefix("Title:") }) {
            return title.replacingOccurrences(of: "Title:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let imported = lines.last(where: { $0.hasPrefix("Imported:") }) {
            return URL(fileURLWithPath: imported.replacingOccurrences(of: "Imported:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)).lastPathComponent
        }

        return lines.suffix(2).joined(separator: "\n")
    }
}

enum SteamLoginTerminalError: LocalizedError {
    case missingScript
    case failedToOpen

    var errorDescription: String? {
        switch self {
        case .missingScript:
            return "Steam login script was not found".localized
        case .failedToOpen:
            return "Could not open Terminal".localized
        }
    }
}

struct SteamLoginStatusChecker {
    static func isLoggedIn(username: String) async -> Bool {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, let steamcmdURL = findSteamcmdURL() else {
            return false
        }

        return await Task.detached(priority: .utility) {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = steamcmdURL
            process.arguments = ["+login", trimmedUsername, "+quit"]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
            } catch {
                return false
            }

            let timeout = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + 45,
                execute: timeout
            )

            process.waitUntilExit()
            timeout.cancel()

            var outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            outputData.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let lowercasedOutput = output.lowercased()

            guard process.terminationStatus == 0 else {
                return false
            }

            if lowercasedOutput.contains("login failure")
                || lowercasedOutput.contains("password")
                || lowercasedOutput.contains("steam guard")
                || lowercasedOutput.contains("failed") {
                return false
            }

            return lowercasedOutput.contains("waiting for user info...ok")
                || lowercasedOutput.contains("logged in ok")
                || lowercasedOutput.contains("success")
        }.value
    }

    private static func findSteamcmdURL() -> URL? {
        let environmentPath = ProcessInfo.processInfo.environment["STEAMCMD"]
        let candidates = [
            environmentPath,
            "/opt/homebrew/bin/steamcmd",
            "/usr/local/bin/steamcmd",
            NSHomeDirectory() + "/steamcmd/steamcmd.sh",
        ].compactMap { $0 }

        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

struct SteamLoginTerminal {
    let username: String
    let password: String

    func open() throws {
        guard let scriptURL = findScriptURL() else {
            throw SteamLoginTerminalError.missingScript
        }

        let supportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("LiveWallpaper", isDirectory: true)

        try FileManager.default.createDirectory(
            at: supportURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let commandURL = supportURL.appendingPathComponent("steamcmd-login.command")
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let contents = """
        #!/usr/bin/env bash
        clear
        COMMAND_FILE="${BASH_SOURCE[0]}"
        rm -f "$COMMAND_FILE"
        \(scriptURL.path.shellQuoted) \(trimmedUsername.shellQuoted) \(password.shellQuoted)
        printf '\\nSteam login finished. You can close this window.\\n'
        read -r -n 1 -s -p 'Press any key to close...'
        printf '\\n'
        """

        try contents.write(to: commandURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: commandURL.path
        )

        guard NSWorkspace.shared.open(commandURL) else {
            throw SteamLoginTerminalError.failedToOpen
        }
    }

    private func findScriptURL() -> URL? {
        let fileManager = FileManager.default
        let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("tools/login_steamcmd.sh"),
            sourceRoot.appendingPathComponent("tools/login_steamcmd.sh"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("tools/login_steamcmd.sh"),
        ].compactMap { $0 }

        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }
}

extension String {
    var shellQuoted: String {
        "'\(replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

// MARK: - Thumbnail Cache
class ThumbnailCache: ObservableObject {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()
    @Published var lastUpdate = Date()

    private init() {
        cache.countLimit = 100

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thumbnailSaved(_:)),
            name: NSNotification.Name("ThumbnailSaved"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thumbnailsGenerated),
            name: NSNotification.Name("ThumbnailsGenerated"),
            object: nil
        )
    }

    @objc private func thumbnailSaved(_ notification: Notification) {
        if let path = notification.userInfo?["path"] as? String {
            cache.removeObject(forKey: path as NSString)
        }
        DispatchQueue.main.async {
            self.lastUpdate = Date()
        }
    }

    @objc private func thumbnailsGenerated() {
        cache.removeAllObjects()
        DispatchQueue.main.async {
            self.lastUpdate = Date()
        }
    }

    func image(for path: String) -> NSImage? {
        if let cached = cache.object(forKey: path as NSString) {
            return cached
        }

        guard FileManager.default.fileExists(atPath: path),
            let img = NSImage(contentsOfFile: path)
        else {
            return nil
        }

        cache.setObject(img, forKey: path as NSString)
        return img
    }

    func clearCache() {
        cache.removeAllObjects()
        lastUpdate = Date()
    }
}

// MARK: - Wallpaper View Model
@MainActor
class WallpaperViewModel: ObservableObject {

    @Published var videos: [VideoItem] = []
    @Published var displays: [DisplayObjc] = []
    @Published var folderPath: String = ""
    @Published var scaleMode: String = "fill"
    @Published var randomOnStartup: Bool = false
    @Published var pauseOnAppFocus: Bool = true
    @Published var volume: Double = 50.0
    @Published var vinttageBar: Bool = true
    @Published var steamLoginStatus: SteamLoginStatus = .idle

    private var currentReloadID = UUID()
    private var steamLoginCheckTask: Task<Void, Never>?
    private let reloadIDLock = NSLock()
    private let defaults = UserDefaults.standard
    let engine: LiveWallpaper

    init(engine: LiveWallpaper = sharedEngine ?? LiveWallpaper.shared()) {
        self.engine = engine
        loadSettings()
        self.engine.setupNotifications()
    }

    func invalidate() {
        cancelSteamLoginStatusChecks()
        engine.removeNotifications()
    }

    func loadSettings() {
        folderPath = engine.getFolderPath()
        scaleMode = defaults.string(forKey: UserDefaultsKeys.scaleMode) ?? "fill"
        randomOnStartup = defaults.bool(forKey: UserDefaultsKeys.randomOnStartup)
        pauseOnAppFocus = defaults.bool(forKey: UserDefaultsKeys.pauseOnAppFocus)
        volume = Double(defaults.float(forKey: UserDefaultsKeys.volumePercentage))
        vinttageBar = defaults.bool(forKey: UserDefaultsKeys.vignetteBar)
    }

    func reloadContent() {
        engine.checkFolderPath()
        ThumbnailCache.shared.clearCache()

        guard let files = try? FileManager.default.contentsOfDirectory(atPath: folderPath) else {
            return
        }

        let videoFiles = files.filter { f in
            let e = (f as NSString).pathExtension.lowercased()
            return e == "mp4" || e == "mov"
        }

        let reloadID = UUID()
        reloadIDLock.lock()
        currentReloadID = reloadID
        reloadIDLock.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let newVideos: [VideoItem] = videoFiles.map { f in
                let full = (self.folderPath as NSString).appendingPathComponent(f)
                let base = (f as NSString).deletingPathExtension
                let thumbPath =
                    (self.engine.thumbnailCachePath() as NSString?)?.appendingPathComponent(
                        "\(base).png") ?? ""

                var item = VideoItem(filename: f, path: full, thumbnailPath: thumbPath)
                self.engine.videoQualityBadge(for: URL(fileURLWithPath: full)) { badge in
                    item.quality = badge
                }
                return item
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                self.reloadIDLock.lock()
                let isValid = reloadID == self.currentReloadID
                self.reloadIDLock.unlock()

                if isValid {
                    self.videos = newVideos

                    let missingThumbnails = newVideos.filter { $0.loadThumbnail() == nil }
                    if !missingThumbnails.isEmpty {
                        NSLog(
                            "Found \(missingThumbnails.count) videos without thumbnails, generating..."
                        )
                        self.engine.generateThumbnails()
                    }
                }
            }
        }
    }

    func loadDisplays() {
        displays = sharedEngine?.getDisplays() as? [DisplayObjc] ?? []
    }

    func startWallpaper(video: VideoItem, displays: [UInt32]) {
        let arr = displays.map { NSNumber(value: $0) }
        engine.startWallpaper(withPath: video.path, onDisplays: arr)
    }

    func stopWallpaper() {
        engine.killAllDaemons()
    }

    func checkSteamLoginStatus() {
        Task {
            _ = await refreshSteamLoginStatus()
        }
    }

    @discardableResult
    private func refreshSteamLoginStatus() async -> Bool {
        let username = defaults.string(forKey: UserDefaultsKeys.steamUsername)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !username.isEmpty else {
            steamLoginStatus = .idle
            return false
        }

        steamLoginStatus = .checking

        let isLoggedIn = await SteamLoginStatusChecker.isLoggedIn(username: username)
        steamLoginStatus = isLoggedIn ? .loggedIn(username) : .loginRequired
        return isLoggedIn
    }

    func scheduleSteamLoginStatusChecks() {
        cancelSteamLoginStatusChecks()
        steamLoginCheckTask = Task { [weak self] in
            for _ in 0..<5 {
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
                if Task.isCancelled { return }
                guard let self else { return }
                if await self.refreshSteamLoginStatus() {
                    return
                }
            }
        }
    }

    func cancelSteamLoginStatusChecks() {
        steamLoginCheckTask?.cancel()
        steamLoginCheckTask = nil
    }

    func resetSteamLoginStatus() {
        cancelSteamLoginStatusChecks()
        steamLoginStatus = .idle
    }

    func clearCache() {
        engine.clearCache()
        ThumbnailCache.shared.clearCache()
        reloadContent()
    }

    func resetUserData() {
        engine.resetUserData()
        loadSettings()
        reloadContent()
    }

    func optimizeVideos() {
        engine.generateStaticWallpapers(forFolder: folderPath) {}
    }

    func importWorkshopItem(_ input: String) async throws -> String {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var targetFolder = folderPath

        if targetFolder.isEmpty {
            targetFolder = engine.getFolderPath()
            folderPath = targetFolder
        }

        try FileManager.default.createDirectory(
            atPath: targetFolder,
            withIntermediateDirectories: true,
            attributes: nil
        )

        engine.selectFolder(targetFolder)
        let steamUsername = defaults.string(forKey: UserDefaultsKeys.steamUsername)
        let output = try await WorkshopImporter(
            importFolder: targetFolder,
            steamUsername: steamUsername
        ).importItem(trimmedInput)
        reloadContent()
        return output
    }

    private func getDisplayName(for id: CGDirectDisplayID) -> String {
        for s in NSScreen.screens {
            if let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                n.uint32Value == id
            {
                return s.localizedName
            }
        }
        return "Display \(id)"
    }
}

#if DEBUG
#Preview {
    ContentView()
}

#Preview {
    SettingsView(viewModel: WallpaperViewModel())
}
#endif
