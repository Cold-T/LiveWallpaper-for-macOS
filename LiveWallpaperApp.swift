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
import ApplicationServices
import ServiceManagement
import Darwin

private let previewDefaultsConfigured: Void = {
    guard LWPrepareBundledRuntime() else { exit(1) }
    var defaults: [String: Any] = [:]
    let environment = ProcessInfo.processInfo.environment
    if let runtime = environment["LIVEWALLPAPER_WINE_RUNTIME"] { defaults["WineRuntimePath"] = runtime }
    if let library = environment["LIVEWALLPAPER_LIBRARY"] { defaults["WallpaperFolder"] = library }
    UserDefaults.standard.register(defaults: defaults)
}()
let sharedEngine: LiveWallpaper? = { _ = previewDefaultsConfigured; return LiveWallpaper.shared() }()

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
    
    let engine = sharedEngine

    func applicationDidFinishLaunching(_ notification: Notification) {
        
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

        // Create main window with ContentView
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView,.borderless],
            backing: .buffered,
            defer: false
        )
        //hide titlebar
        //window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.toolbarStyle = .unified
        
        window.center()
        window.contentView = NSHostingView(rootView: ContentView())
        window.title = "Livewallpaper for macOS"
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // The preview does not register login items or prompt for Accessibility.

        

        

        
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

    // Hide the window without quitting the app
    @objc func hideWindow() {
        window.orderOut(nil)
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

        quitItem = NSMenuItem(title: "", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        updateStatusMenu()
        return menu
    }

    private func updateStatusMenu() {
        toggleWallpaperItem.title = isWallpaperRunning
            ? menuText(zh: "停止壁纸", en: "Stop Wallpaper")
            : menuText(zh: "开始壁纸", en: "Start Wallpaper")
        showWindowItem.title = menuText(zh: "显示主界面", en: "Show Main Window")
        nextWallpaperItem.title = menuText(zh: "下一个壁纸", en: "Next Wallpaper")
        nextWallpaperItem.isEnabled = isWallpaperRunning
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

// MARK: Permission Access

func hasAccessibilityAccess() -> Bool {
    return AXIsProcessTrusted()
}

func requestAccessibilityAccess() {
    let options: [String: Bool] = ["AXTrustedCheckOptionPrompt": true]
    AXIsProcessTrustedWithOptions(options as CFDictionary)
}

func isLoginItemEnabled() -> Bool {
    return UserDefaults.standard.bool(forKey: UserDefaultsKeys.launchAtLogin)
}


func setLoginItem(enabled: Bool) {
    guard let bundleId = Bundle.main.bundleIdentifier else { return }

    if SMLoginItemSetEnabled(bundleId as CFString, enabled) {
        UserDefaults.standard.set(enabled, forKey: UserDefaultsKeys.launchAtLogin)
    } else {
        print("❌ Failed to update login items")
    }
}
