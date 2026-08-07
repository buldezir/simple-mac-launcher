import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class LauncherPanelController: NSObject {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<SearchView>?
    private let model: LauncherViewModel
    private var hideObserver: NSObjectProtocol?
    private var clickMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var pendingFit: DispatchWorkItem?
    private var lastFittedSize: NSSize = .zero
    /// Screen maxY of the panel — kept stable across height changes so the
    /// search field doesn't jump when results shrink or grow.
    private var anchoredMaxY: CGFloat?
    private var resizeDisplayLink: CADisplayLink?
    private var resizeStartTime: CFTimeInterval = 0
    private var resizeStartFrame: NSRect = .zero
    private var resizeTargetFrame: NSRect = .zero
    /// Bumped to cancel an in-flight dismiss animation (e.g. show during hide).
    private var dismissGeneration = 0

    private static let resizeDuration: CFTimeInterval = 0.18
    /// Alfred-style quick fade + shrink on dismiss.
    private static let dismissDuration: CFTimeInterval = 0.14
    private static let dismissScale: CGFloat = 0.94

    init(model: LauncherViewModel) {
        self.model = model
        super.init()
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
                // Wait until @Published values + SwiftUI layout commit before measuring.
                self?.scheduleFitPanelToContent(animated: true)
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
        resizeDisplayLink?.invalidate()
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        dismissGeneration += 1
        model.resetForShow()
        let panel = ensurePanel()
        stopHeightAnimation()
        resetPanelAppearance(panel)
        fitPanelToContent(animated: false)
        position(panel)
        KeyboardLayoutSwitcher.activateEnglish()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .launcherPanelDidShow, object: nil)
        startClickOutsideMonitor()
    }

    func hide() {
        stopHeightAnimation()
        stopClickOutsideMonitor()
        model.ai.cancel()

        guard let panel, panel.isVisible else {
            KeyboardLayoutSwitcher.restorePrevious()
            return
        }

        guard let content = panel.contentView, let layer = content.layer else {
            finishHide(panel)
            return
        }

        dismissGeneration += 1
        let generation = dismissGeneration
        let scale = Self.dismissScale
        let bounds = layer.bounds
        // Scale toward center without touching anchorPoint (AppKit-managed layers).
        let tx = bounds.width * (1 - scale) / 2
        let ty = bounds.height * (1 - scale) / 2
        var transform = CATransform3DMakeTranslation(tx, ty, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)

        CATransaction.begin()
        CATransaction.setAnimationDuration(Self.dismissDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeIn))
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor in
                guard let self, self.dismissGeneration == generation else { return }
                self.finishHide(panel)
            }
        }
        layer.opacity = 0
        layer.transform = transform
        CATransaction.commit()
    }

    private func finishHide(_ panel: NSPanel) {
        panel.orderOut(nil)
        resetPanelAppearance(panel)
        KeyboardLayoutSwitcher.restorePrevious()
    }

    private func resetPanelAppearance(_ panel: NSPanel) {
        guard let content = panel.contentView, let layer = content.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 1
        layer.transform = CATransform3DIdentity
        CATransaction.commit()
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
        // Prevent system utility-window chrome animations from shifting the panel.
        panel.animationBehavior = .none

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

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel, self.resizeDisplayLink?.isPaused != false else { return }
                self.anchoredMaxY = panel.frame.maxY
            }
        }

        return panel
    }

    private func scheduleFitPanelToContent(animated: Bool) {
        pendingFit?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.fitPanelToContent(animated: animated)
        }
        pendingFit = work
        // Next turn: property updates applied and SwiftUI has laid out.
        DispatchQueue.main.async(execute: work)
    }

    private func fitPanelToContent(animated: Bool) {
        guard let panel, let hostingView else { return }

        // Measure the settled (non-animating) SwiftUI layout.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            hostingView.invalidateIntrinsicContentSize()
        }
        hostingView.layoutSubtreeIfNeeded()

        let size = hostingView.fittingSize
        let width = max(size.width, 640)
        let height = max(size.height, 72)
        let maxHeight = (NSScreen.main?.visibleFrame.height ?? 900) * 0.55
        let cappedHeight = min(height, maxHeight)
        let targetSize = NSSize(width: width, height: cappedHeight)

        // Selection / no-op updates otherwise thrash setFrame every keystroke.
        if abs(targetSize.width - lastFittedSize.width) < 0.5,
           abs(targetSize.height - lastFittedSize.height) < 0.5 {
            return
        }
        lastFittedSize = targetSize

        // Prefer the in-flight animation target's top so rapid typing doesn't
        // compound mid-animation frame samples into vertical drift.
        let currentMaxY: CGFloat
        if resizeDisplayLink != nil {
            currentMaxY = anchoredMaxY ?? resizeTargetFrame.maxY
        } else {
            currentMaxY = panel.frame.maxY
            anchoredMaxY = currentMaxY
        }

        let targetFrame = NSRect(
            x: panel.frame.origin.x,
            y: currentMaxY - cappedHeight,
            width: width,
            height: cappedHeight
        )

        let heightDelta = abs(panel.frame.height - cappedHeight)
        let shouldAnimate = animated && panel.isVisible && heightDelta >= 6
        if shouldAnimate {
            startHeightAnimation(to: targetFrame)
        } else {
            stopHeightAnimation()
            panel.setFrame(targetFrame, display: true)
        }
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        // Anchor by the top edge so later height changes don't re-center the window.
        let topY = visible.midY + visible.height * 0.15 + size.height / 2
        let y = topY - size.height
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        anchoredMaxY = panel.frame.maxY
    }

    // MARK: - Top-anchored height animation

    private func startHeightAnimation(to target: NSRect) {
        guard let panel else { return }

        resizeStartFrame = panel.frame
        resizeTargetFrame = target
        anchoredMaxY = target.maxY
        resizeStartTime = CACurrentMediaTime()

        if resizeDisplayLink == nil {
            let link = panel.displayLink(target: self, selector: #selector(handleResizeTick))
            link.add(to: .main, forMode: .common)
            resizeDisplayLink = link
        }
        resizeDisplayLink?.isPaused = false
    }

    private func stopHeightAnimation() {
        resizeDisplayLink?.isPaused = true
    }

    @objc private func handleResizeTick(_ link: CADisplayLink) {
        guard let panel else {
            stopHeightAnimation()
            return
        }

        let elapsed = CACurrentMediaTime() - resizeStartTime
        let progress = min(1, elapsed / Self.resizeDuration)
        // Ease in-out cubic
        let t = progress < 0.5
            ? 4 * progress * progress * progress
            : 1 - pow(-2 * progress + 2, 3) / 2

        let maxY = anchoredMaxY ?? resizeTargetFrame.maxY
        let height = resizeStartFrame.height + (resizeTargetFrame.height - resizeStartFrame.height) * t
        let width = resizeStartFrame.width + (resizeTargetFrame.width - resizeStartFrame.width) * t
        let frame = NSRect(
            x: resizeTargetFrame.origin.x,
            y: maxY - height,
            width: width,
            height: height
        )
        panel.setFrame(frame, display: true)

        if progress >= 1 {
            panel.setFrame(resizeTargetFrame, display: true)
            stopHeightAnimation()
        }
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
