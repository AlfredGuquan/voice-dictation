// F6 tracer: locate dashed-box border artifact on floating pill
// Run: swift tracer/v03-gui/F6-pill-border/demo.swift <variant>
//   variant: prod | no-border | no-focusring | no-shadow | no-overlay | ve-only | fixed
//
// Renders the same NSPanel + PillViewController config as production, with one
// toggle disabled per variant, to binary-search the source of the dashed box.

import Cocoa

let variant = CommandLine.arguments.dropFirst().first ?? "prod"
print("[F6] variant=\(variant)")

final class PillPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PillVC: NSViewController {
    let variant: String
    private let pillWidth: CGFloat = 280
    private let pillHeight: CGFloat = 48

    init(variant: String) { self.variant = variant; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: pillWidth, height: pillHeight))
        self.view = root

        let container = NSView(frame: root.bounds)
        container.wantsLayer = true
        container.layer?.cornerRadius = pillHeight / 2
        container.layer?.masksToBounds = true
        root.addSubview(container)

        let ve = NSVisualEffectView(frame: container.bounds)
        ve.material = .hudWindow
        ve.blendingMode = .behindWindow
        ve.state = .active
        ve.wantsLayer = true
        container.addSubview(ve)

        if variant != "ve-only" {
            let overlay = NSView(frame: container.bounds)
            overlay.wantsLayer = true
            let bg = NSColor(red: 1.0, green: 0.99, blue: 0.98, alpha: 0.82)
            overlay.layer?.backgroundColor = bg.cgColor
            if variant != "no-overlay" {
                container.addSubview(overlay)
            }
        }

        // PROD: borderWidth=1 on container
        if variant != "no-border" && variant != "fixed" {
            container.layer?.borderWidth = 1
            container.layer?.borderColor = NSColor(white: 0, alpha: 0.06).cgColor
        }

        root.wantsLayer = true
        if variant != "no-shadow" {
            root.shadow = NSShadow()
            root.layer?.shadowColor = NSColor(white: 0, alpha: 0.15).cgColor
            root.layer?.shadowOffset = CGSize(width: 0, height: -4)
            root.layer?.shadowRadius = 24
            root.layer?.shadowOpacity = 1
        }

        // dots for sanity
        let dot1 = NSView(frame: NSRect(x: 16, y: 20, width: 8, height: 8))
        dot1.wantsLayer = true
        dot1.layer?.cornerRadius = 4
        dot1.layer?.backgroundColor = NSColor(red: 196/255, green: 101/255, blue: 58/255, alpha: 1).cgColor
        container.addSubview(dot1)

        let dot2 = NSView(frame: NSRect(x: pillWidth - 24, y: 20, width: 8, height: 8))
        dot2.wantsLayer = true
        dot2.layer?.cornerRadius = 4
        dot2.layer?.backgroundColor = NSColor(red: 93/255, green: 140/255, blue: 90/255, alpha: 1).cgColor
        container.addSubview(dot2)
    }
}

func makePanel(variant: String) -> PillPanel? {
    // Always use built-in display (screen with frame origin at 0,0) so screencapture -x captures it
    let screen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main
    guard let screen = screen else { return nil }
    let w: CGFloat = 280; let h: CGFloat = 48
    let f = screen.visibleFrame
    let panel = PillPanel(
        contentRect: NSRect(x: f.midX - w/2, y: f.minY + 40, width: w, height: h),
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

    // PROD keeps default — we toggle explicitly
    if variant == "no-focusring" || variant == "fixed" {
        // No direct API on NSPanel to disable focus ring since borderless has none,
        // but try setting contentView.focusRingType
    }

    panel.contentViewController = PillVC(variant: variant)

    if variant == "fixed" || variant == "no-focusring" {
        panel.contentView?.focusRingType = .none
    }

    return panel
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

guard let panel = makePanel(variant: variant) else {
    fputs("no screen\n", stderr); exit(1)
}
panel.orderFrontRegardless()
print("[F6] pill visible at \(panel.frame) — screenshotting in 1.2s")

DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
    let path = "/tmp/f6-\(variant).png"
    let task = Process()
    task.launchPath = "/usr/sbin/screencapture"
    task.arguments = ["-x", "-D", "1", path]
    try? task.run()
    task.waitUntilExit()
    print("[F6] saved \(path)")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        NSApp.terminate(nil)
    }
}

app.run()
