import Cocoa
import SwiftUI

/// App-internal floating toast manager (F5).
/// Runtime errors/info surface here instead of macOS notification center.
/// Startup errors (missing API key, missing accessibility) keep using osascript
/// because the toast render path isn't reliable during early app launch.
final class ToastManager {

    enum Kind {
        case error   // 3s, hover-pause, close button
        case info    // 2s, transient, no controls
    }

    static let shared = ToastManager()

    private let maxStack = 4
    private let topInset: CGFloat = 36
    private let rightInset: CGFloat = 16
    private let spacing: CGFloat = 6
    private let toastWidth: CGFloat = 320
    private let toastHeight: CGFloat = 32

    private var active: [ToastItem] = []

    private init() {}

    // MARK: - Public API

    func show(_ kind: Kind, message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.present(kind: kind, message: message)
        }
    }

    // MARK: - Internals

    private final class ToastItem {
        let panel: ToastPanel
        let vc: NSHostingController<ToastView>
        var timer: Timer?
        var dismissed = false

        init(panel: ToastPanel, vc: NSHostingController<ToastView>) {
            self.panel = panel
            self.vc = vc
        }
    }

    private func present(kind: Kind, message: String) {
        // Enforce stack cap — evict oldest.
        while active.count >= maxStack {
            dismiss(active.first!, animated: false)
        }

        guard let screen = NSScreen.main else { return }

        let panel = ToastPanel(
            contentRect: NSRect(x: 0, y: 0, width: toastWidth, height: toastHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = (kind == .info)  // info toasts are pure glance
        panel.animationBehavior = .none

        var item: ToastItem!
        let view = ToastView(
            kind: kind,
            message: message,
            onClose: { [weak self] in
                guard let self = self, let it = item else { return }
                self.dismiss(it, animated: true)
            },
            onHoverChange: { [weak self] hovering in
                guard let self = self, let it = item, kind == .error else { return }
                if hovering {
                    it.timer?.invalidate()
                    it.timer = nil
                } else {
                    self.scheduleDismiss(it, after: self.duration(for: kind))
                }
            }
        )
        let host = NSHostingController(rootView: view)
        host.view.frame = NSRect(x: 0, y: 0, width: toastWidth, height: toastHeight)
        panel.contentView = host.view
        panel.contentViewController = host

        item = ToastItem(panel: panel, vc: host)
        active.append(item)

        // Position + animate-in. Count only non-dismissed items so this new toast
        // lands in the first visible slot (dismissed items stay in `active` until
        // their fade-out animation completes).
        let visibleIndex = active.filter { !$0.dismissed }.count - 1
        let targetFrame = frameForIndex(max(0, visibleIndex), screen: screen)
        var startFrame = targetFrame
        startFrame.origin.x += 32  // slide in from right
        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.3, 1)
            panel.animator().setFrame(targetFrame, display: true)
            panel.animator().alphaValue = 1
        }

        // Re-layout older toasts downward.
        relayout(screen: screen)

        scheduleDismiss(item, after: duration(for: kind))
    }

    private func duration(for kind: Kind) -> TimeInterval {
        switch kind {
        case .error: return 3.0
        case .info:  return 2.0
        }
    }

    private func scheduleDismiss(_ item: ToastItem, after seconds: TimeInterval) {
        item.timer?.invalidate()
        item.timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self, weak item] _ in
            guard let self = self, let item = item else { return }
            self.dismiss(item, animated: true)
        }
    }

    private func dismiss(_ item: ToastItem, animated: Bool) {
        guard !item.dismissed else { return }
        item.dismissed = true
        item.timer?.invalidate()
        item.timer = nil

        let finish: () -> Void = { [weak self, weak item] in
            guard let self = self, let item = item else { return }
            item.panel.orderOut(nil)
            // Break the SwiftUI->closure->item retain cycle:
            // view closures (onClose/onHoverChange) capture `item`, item keeps panel,
            // panel keeps contentViewController, host keeps its view, view hosts SwiftUI
            // tree that holds the closures. Severing the panel->vc/view edge drops it.
            item.panel.contentViewController = nil
            item.panel.contentView = nil
            self.active.removeAll { $0 === item }
            if let screen = NSScreen.main {
                self.relayout(screen: screen)
            }
        }

        if animated {
            let endFrame = {
                var f = item.panel.frame
                f.origin.x += 24
                return f
            }()
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                item.panel.animator().setFrame(endFrame, display: true)
                item.panel.animator().alphaValue = 0
            }, completionHandler: finish)
        } else {
            finish()
        }
    }

    private func frameForIndex(_ index: Int, screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let x = visible.maxX - toastWidth - rightInset
        // NSScreen y is bottom-up: topInset is distance from top of visibleFrame.
        let y = visible.maxY - topInset - toastHeight - CGFloat(index) * (toastHeight + spacing)
        return NSRect(x: x, y: y, width: toastWidth, height: toastHeight)
    }

    private func relayout(screen: NSScreen) {
        // Skip items currently fading out — otherwise we'd re-slot a dismissed
        // panel to a new position while its dismiss animation is still running,
        // producing a visible "jump a row then disappear" artefact.
        var slot = 0
        for item in active {
            if item.dismissed { continue }
            let target = frameForIndex(slot, screen: screen)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                item.panel.animator().setFrame(target, display: true)
            }
            slot += 1
        }
    }
}
