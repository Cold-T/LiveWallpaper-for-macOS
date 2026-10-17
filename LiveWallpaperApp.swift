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

import SwiftUI
import AppKit
import Darwin

private let runtimeDefaultsConfigured: Void = {
    guard LWPrepareBundledRuntime() else { exit(1) }
    var defaults: [String: Any] = [:]
    let environment = ProcessInfo.processInfo.environment
    if let runtime = environment["LIVEWALLPAPER_WINE_RUNTIME"] { defaults["WineRuntimePath"] = runtime }
    if let library = environment["LIVEWALLPAPER_LIBRARY"] { defaults["WallpaperFolder"] = library }
    UserDefaults.standard.register(defaults: defaults)
}()
let sharedEngine: LiveWallpaper? = { _ = runtimeDefaultsConfigured; return LiveWallpaper.shared() }()

@main
struct LiveWallpaperApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        // The app owns its AppKit window and status item. An empty SwiftUI
        // Settings scene creates an extra window on recent macOS releases.
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit Livewallpaper for macOS", action: #selector(AppDelegate.quit), keyEquivalent: "q")
        quitItem.target = delegate
        applicationMenu.addItem(quitItem)
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        // Standard responder-chain actions are needed by SwiftUI text fields
        // hosted inside our AppKit window, including settings sheets.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        let undo = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(undo)
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        application.mainMenu = mainMenu
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var window: NSWindow!
    private var toggleWallpaperItem: NSMenuItem!
    private var showWindowItem: NSMenuItem!
    private var nextWallpaperItem: NSMenuItem!
    private var quitItem: NSMenuItem!
    private var volumeSlider: NSSlider!
    private var volumeLabel: NSTextField!

    private var playbackReady = false
    var engine: LiveWallpaper? { playbackReady ? sharedEngine : nil }

    func applicationDidFinishLaunching(_ notification: Notification) {

        _ = runtimeDefaultsConfigured
        // The frontend-only edition can manage and play native videos without Wine.
        // Only editions carrying setup components require the first-run wizard.
        let includesSetup = Bundle.main.url(forResource: "SetupRuntime", withExtension: "json") != nil
        playbackReady = !includesSetup || LWSetupRuntimeReady()
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let statusIcon = NSImage(named: "LiveWallpaperStatusIcon")
                ?? NSImage(named: NSImage.applicationIconName)
                ?? NSImage(systemSymbolName: "play.desktopcomputer", accessibilityDescription: "Livewallpaper for macOS")
            statusIcon?.size = NSSize(width: 18, height: 18)
            statusIcon?.isTemplate = false
            button.image = statusIcon
            button.toolTip = "Livewallpaper for macOS"
        }
        statusItem.menu = makeStatusMenu()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView,.borderless],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.toolbarStyle = .unified

        window.center()
        if playbackReady {
            window.contentView = NSHostingView(rootView: ContentView())
        } else {
            window.contentView = NSHostingView(rootView: FirstRunSetupView(onComplete: { [weak self] in
                guard let self else { return }
                self.playbackReady = true
                self.window.contentView = NSHostingView(rootView: ContentView())
                self.updateStatusMenu()
            }))
        }
        window.title = "Livewallpaper for macOS"
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

    }

    func applicationWillTerminate(_ notification: Notification) {
        engine?.killAllDaemons()
    }

    // Show the config window
    @objc func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .liveWallpaperShouldRefresh, object: nil)

    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    // Quit the app completely
    @objc func quit() {

        engine?.terminateApplication()
        NSApp.terminate(nil)
    }

    @objc func toggleWallpaper() {
        if isWallpaperRunning {
            engine?.killAllDaemons()
        } else {
            engine?.startLastWallpaper()
        }
        updateStatusMenu()
    }

    @objc func nextWallpaper() {
        engine?.nextWallpaper()
        updateStatusMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateStatusMenu()
    }

    private var isWallpaperRunning: Bool {
        engine?.isWallpaperRunning ?? false
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        toggleWallpaperItem = NSMenuItem(title: "", action: #selector(toggleWallpaper), keyEquivalent: "p")
        toggleWallpaperItem.target = self
        menu.addItem(toggleWallpaperItem)

        showWindowItem = NSMenuItem(title: "", action: #selector(showWindow), keyEquivalent: "s")
        showWindowItem.target = self
        menu.addItem(showWindowItem)

        nextWallpaperItem = NSMenuItem(title: "", action: #selector(nextWallpaper), keyEquivalent: "n")
        nextWallpaperItem.target = self
        menu.addItem(nextWallpaperItem)

        menu.addItem(NSMenuItem.separator())
        let volumeItem = NSMenuItem()
        let volumeView = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 58))
        volumeLabel = NSTextField(labelWithString: "")
        volumeLabel.frame = NSRect(x: 18, y: 33, width: 204, height: 18)
        volumeSlider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: self, action: #selector(changeVolume(_:)))
        volumeSlider.frame = NSRect(x: 18, y: 7, width: 204, height: 24)
        volumeSlider.isContinuous = true
        volumeSlider.setAccessibilityLabel(menuText(zh: "壁纸音量", en: "Wallpaper volume"))
        volumeView.addSubview(volumeLabel)
        volumeView.addSubview(volumeSlider)
        volumeItem.view = volumeView
        menu.addItem(volumeItem)
        menu.addItem(NSMenuItem.separator())

        quitItem = NSMenuItem(title: "", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        updateStatusMenu()
        return menu
    }

    @objc private func changeVolume(_ sender: NSSlider) {
        engine?.updateVolume(sender.doubleValue.rounded())
        updateVolumeControl()
    }

    private func updateVolumeControl() {
        let value = min(100, max(0, UserDefaults.standard.double(forKey: UserDefaultsKeys.volumePercentage)))
        volumeSlider?.doubleValue = value
        volumeLabel?.stringValue = "\(menuText(zh: "壁纸音量", en: "Wallpaper volume"))  \(Int(value))%"
    }

    private func updateStatusMenu() {
        updateVolumeControl()
        toggleWallpaperItem.title = isWallpaperRunning
            ? menuText(zh: "停止壁纸", en: "Stop Wallpaper")
            : menuText(zh: "开始壁纸", en: "Start Wallpaper")
        showWindowItem.title = menuText(zh: "显示主界面", en: "Show Main Window")
        nextWallpaperItem.title = menuText(zh: "下一个壁纸", en: "Next Wallpaper")
        nextWallpaperItem.isEnabled = isWallpaperRunning
        toggleWallpaperItem.isEnabled = playbackReady
        volumeSlider?.isEnabled = playbackReady
        quitItem.title = menuText(zh: "退出", en: "Quit")
    }

    private func menuText(zh: String, en: String) -> String {
        menuLanguageCode.hasPrefix("zh") ? zh : en
    }

    private var menuLanguageCode: String {
        let selectedLanguage = UserDefaults.standard.string(forKey: UserDefaultsKeys.appLanguage) ?? "auto"
        if selectedLanguage == "auto" {
            return Locale.preferredLanguages.first ?? "en"
        }
        return selectedLanguage
    }
}
