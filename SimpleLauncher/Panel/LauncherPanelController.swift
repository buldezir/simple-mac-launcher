import AppKit
import Combine
import SwiftUI

@MainActor
final class LauncherPanelController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<SearchView>?
    private let model: LauncherViewModel
    private var hideObserver: NSObjectProtocol?
    private var clickMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    init(model: LauncherViewModel) {
        self.model = model
        hideObserver = NotificationCenter.default.addObserver(
            forName: .launcherShouldHide,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }

        model.objectWillChange
            .merge(with: model.ai.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.fitPanelToContent()
            }
            .store(in: &cancellables)
    }

    deinit {
        if let hideObserver {
            NotificationCenter.default.removeObserver(hideObserver)
        }
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        model.resetForShow()
        let panel = ensurePanel()
        fitPanelToContent()
        position(panel)
        KeyboardLayoutSwitcher.activateEnglish()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .launcherPanelDidShow, object: nil)
        startClickOutsideMonitor()
    }

    func hide() {
        panel?.orderOut(nil)
        stopClickOutsideMonitor()
        model.ai.cancel()
        KeyboardLayoutSwitcher.restorePrevious()
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        // Do not combine .canJoinAllSpaces with .moveToActiveSpace — AppKit aborts.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // SwiftUI draws the soft shadow; window shadow is square
        panel.animationBehavior = .utilityWindow

        let root = SearchView(model: model)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting
        if let contentView = panel.contentView {
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = NSColor.clear.cgColor
        }
        hostingView = hosting
        self.panel = panel
        return panel
    }

    private func fitPanelToContent() {
        guard let panel, let hostingView else { return }
        hostingView.invalidateIntrinsicContentSize()
        let size = hostingView.fittingSize
        let width = max(size.width, 640)
        let height = max(size.height, 72)
        var frame = panel.frame
        let maxHeight = (NSScreen.main?.visibleFrame.height ?? 900) * 0.55
        let cappedHeight = min(height, maxHeight)
        frame.origin.y += frame.size.height - cappedHeight
        frame.size = NSSize(width: width, height: cappedHeight)
        panel.setFrame(frame, display: true)
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.midY + visible.height * 0.15 - size.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func startClickOutsideMonitor() {
        stopClickOutsideMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel, panel.isVisible else { return }
                if !panel.frame.contains(NSEvent.mouseLocation) {
                    self.hide()
                }
            }
        }
    }

    private func stopClickOutsideMonitor() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }
}

/// Borderless panels cannot become key by default; override so the search field can focus.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
