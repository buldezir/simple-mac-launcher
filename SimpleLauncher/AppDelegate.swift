import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var updateItem: NSMenuItem?
    private var panelController: LauncherPanelController?
    private var settingsWindow: NSWindow?
    private let model = LauncherViewModel()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppUpdater.shared.start()

        panelController = LauncherPanelController(model: model)

        HotkeyManager.shared.onToggle = { [weak self] in
            self?.panelController?.toggle()
        }
        SettingsStore.shared.$activationHotkey
            .receive(on: RunLoop.main)
            .sink { hotkey in
                HotkeyManager.shared.register(hotkey)
            }
            .store(in: &cancellables)

        SettingsStore.shared.$showMenuBarIcon
            .receive(on: RunLoop.main)
            .sink { [weak self] show in
                self?.updateStatusItem(visible: show)
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: .launcherShowSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.openSettings()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregister()
    }

    private func updateStatusItem(visible: Bool) {
        if visible {
            guard statusItem == nil else { return }
            setupStatusItem()
        } else {
            removeStatusItem()
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "bolt.circle.fill", accessibilityDescription: "Simple Launcher")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        let showItem = NSMenuItem(title: "Show Launcher", action: #selector(showLauncher), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        self.updateItem = updateItem

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func removeStatusItem() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    @objc func showLauncher() {
        panelController?.show()
    }

    @objc func openSettings() {
        if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(settings: SettingsStore.shared)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Simple Launcher Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 560, height: 740))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    @objc private func checkForUpdates() {
        AppUpdater.shared.checkForUpdates()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate, NSMenuItemValidation {
    /// The update item offers the update a daily check found, if any.
    func menuWillOpen(_ menu: NSMenu) {
        updateItem?.isHidden = !AppUpdater.shared.isRelease
        updateItem?.title = AppUpdater.shared.menuTitle
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(checkForUpdates) else { return true }
        return AppUpdater.shared.canCheck || AppUpdater.shared.available != nil
    }
}
