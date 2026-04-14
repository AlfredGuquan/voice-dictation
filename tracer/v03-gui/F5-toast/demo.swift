// F5 tracer: app-internal toast as floating NSPanel
// Run: swift tracer/v03-gui/F5-toast/demo.swift
//
// Verifies:
// 1. NSPanel (nonactivating + canBecomeKey=false + hidesOnDeactivate=false + .floating + .canJoinAllSpaces)
//    remains visible when foreground app changes (Finder, TextEdit, Safari etc).
// 2. slide-in + fade animation via NSAnimationContext.
// 3. auto-dismiss Timer + stacking strategy (N toasts stack vertically, oldest at top).
//
// Interaction:
// - press 'T' in Terminal (or just wait 2s) to queue new toasts
// - switch focus to Finder/TextEdit during the 6s run — toasts must remain visible

import Cocoa

// MARK: - ToastPanel

final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    static func create(message: String, level: ToastLevel) -> ToastPanel? {
        guard let screen = NSScreen.main else { return nil }
        let width: CGFloat = 320
        let height: CGFloat = 44
        let frame = NSRect(x: 0, y: 0, width: width, height: height)

        let panel = ToastPanel(
            contentRect: frame,
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
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.ignoresMouseEvents = true  // toasts non-interactive

        let vc = ToastViewController(message: message, level: level)
        panel.contentViewController = vc
        _ = screen  // suppress unused warning
        return panel
    }
}

enum ToastLevel {
    case info, warning, error
    var accent: NSColor {
        switch self {
        case .info:    return NSColor(red: 93/255, green: 140/255, blue: 90/255, alpha: 1.0)   // green
        case .warning: return NSColor(red: 217/255, green: 119/255, blue: 87/255, alpha: 1.0)  // orange
        case .error:   return NSColor(red: 196/255, green: 78/255, blue: 58/255, alpha: 1.0)   // red
        }
    }
}

// MARK: - ToastViewController

final class ToastViewController: NSViewController {
    private let message: String
    private let level: ToastLevel
    private let bg = NSColor(red: 1.0, green: 0.99, blue: 0.98, alpha: 0.92)

    init(message: String, level: ToastLevel) {
        self.message = message
        self.level = level
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 44))
        root.wantsLayer = true

        let container = NSView(frame: root.bounds)
        container.wantsLayer = true
        container.layer?.cornerRadius = 22
        container.layer?.masksToBounds = true
        root.addSubview(container)

        // frosted glass
        let ve = NSVisualEffectView(frame: container.bounds)
        ve.material = .hudWindow
        ve.blendingMode = .behindWindow
        ve.state = .active
        container.addSubview(ve)

        // warm overlay
        let overlay = NSView(frame: container.bounds)
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = bg.cgColor
        container.addSubview(overlay)

        // accent dot
        let dot = NSView(frame: NSRect(x: 16, y: 18, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = level.accent.cgColor
        container.addSubview(dot)

        // text
        let label = NSTextField(frame: NSRect(x: 32, y: 12, width: 272, height: 20))
        label.stringValue = message
        label.isEditable = false
        label.isBordered = false
        label.isSelectable = false
        label.backgroundColor = .clear
        label.textColor = NSColor(red: 107/255, green: 101/255, blue: 96/255, alpha: 1.0)
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        container.addSubview(label)

        // shadow
        root.shadow = NSShadow()
        root.layer?.shadowColor = NSColor(white: 0, alpha: 0.18).cgColor
        root.layer?.shadowOffset = CGSize(width: 0, height: -4)
        root.layer?.shadowRadius = 20
        root.layer?.shadowOpacity = 1

        self.view = root
    }
}

// MARK: - ToastManager

final class ToastManager {
    static let shared = ToastManager()

    private struct Entry {
        let panel: ToastPanel
        var timer: Timer?
    }

    private var entries: [Entry] = []
    private let spacing: CGFloat = 8
    private let bottomMargin: CGFloat = 100  // above pill (pill sits at +40)
    private let maxStack = 4
    private let duration: TimeInterval = 3.0

    func show(_ message: String, level: ToastLevel = .info) {
        guard let panel = ToastPanel.create(message: message, level: level),
              let screen = NSScreen.main else { return }

        // evict oldest if at cap
        if entries.count >= maxStack, let oldest = entries.first {
            dismiss(oldest.panel, animated: true)
        }

        let screenFrame = screen.visibleFrame
        let targetX = screenFrame.midX - panel.frame.width / 2
        // stack upward
        let stackIdx = entries.count
        let targetY = screenFrame.minY + bottomMargin + CGFloat(stackIdx) * (panel.frame.height + spacing)

        // start off-screen right for slide-in
        var startFrame = panel.frame
        startFrame.origin = CGPoint(x: targetX + 40, y: targetY)
        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            var target = startFrame
            target.origin.x = targetX
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }

        let timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self, weak panel] _ in
            guard let self = self, let panel = panel else { return }
            self.dismiss(panel, animated: true)
        }
        entries.append(Entry(panel: panel, timer: timer))
        print("[toast] shown '\(message)' at stack idx \(stackIdx) — total=\(entries.count)")
    }

    private func dismiss(_ panel: ToastPanel, animated: Bool) {
        guard let idx = entries.firstIndex(where: { $0.panel === panel }) else { return }
        entries[idx].timer?.invalidate()
        entries.remove(at: idx)

        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
        } else {
            panel.orderOut(nil)
        }

        // relayout remaining
        relayout()
    }

    private func relayout() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        for (idx, entry) in entries.enumerated() {
            let targetY = screenFrame.minY + bottomMargin + CGFloat(idx) * (entry.panel.frame.height + 8)
            var frame = entry.panel.frame
            frame.origin.y = targetY
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                entry.panel.animator().setFrame(frame, display: true)
            }
        }
    }
}

// MARK: - Driver

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

class Driver: NSObject {
    var tickCount = 0
    @objc func fire() {
        tickCount += 1
        let levels: [ToastLevel] = [.info, .warning, .error]
        let messages = [
            "Recording failed to start",
            "Pipeline error: network timeout",
            "No focused text field — copied to clipboard",
            "Audio archived — retry later",
            "Dictation injected",
        ]
        ToastManager.shared.show(messages[tickCount % messages.count], level: levels[tickCount % 3])
        if tickCount >= 6 {
            print("[driver] all toasts queued — observe for 5s then exit")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                print("[driver] exiting")
                NSApp.terminate(nil)
            }
        }
    }
}

let driver = Driver()
// fire toasts at 0s, 0.4s, 0.8s, 1.2s, 1.6s, 2.0s to test stacking + eviction
for i in 0..<6 {
    Timer.scheduledTimer(timeInterval: Double(i) * 0.4, target: driver, selector: #selector(Driver.fire), userInfo: nil, repeats: false)
}

print("[main] NSPanel toast demo — watch screen bottom. Switch to Finder during run to verify still visible.")
app.run()
