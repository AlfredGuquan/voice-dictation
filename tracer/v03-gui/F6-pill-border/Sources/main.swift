// F6 tracer (production code): instantiate the real FloatingPillPanel + PillViewController
// + test hypothesis by toggling shadow configuration
//
// Args: prod | no-nsshadow | shadow-on-container | no-masks-to-bounds | fixed

import Cocoa

let variant = CommandLine.arguments.dropFirst().first ?? "prod"
print("[F6-prod] variant=\(variant)")

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screenOpt = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main
guard let screen = screenOpt else { fputs("no screen\n", stderr); exit(1) }

guard let panel = FloatingPillPanel.create() else { exit(1) }
let f = screen.visibleFrame
var frame = panel.frame
frame.origin.x = f.midX - frame.width / 2
frame.origin.y = f.minY + 40
panel.setFrame(frame, display: false)

let vc = PillViewController()
panel.contentViewController = vc

DispatchQueue.main.async {
    let rootView = vc.view
    switch variant {
    case "no-nsshadow":
        rootView.shadow = nil
    case "shadow-on-container":
        rootView.shadow = nil
        rootView.layer?.shadowOpacity = 0
        if let container = rootView.subviews.first {
            container.wantsLayer = true
            container.layer?.masksToBounds = false
            container.shadow = NSShadow()
            container.layer?.shadowColor = NSColor(white: 0, alpha: 0.15).cgColor
            container.layer?.shadowOffset = CGSize(width: 0, height: -4)
            container.layer?.shadowRadius = 24
            container.layer?.shadowOpacity = 1
        }
    case "no-masks-to-bounds":
        if let container = rootView.subviews.first {
            container.layer?.masksToBounds = false
        }
    case "fixed":
        rootView.shadow = nil
        if let layer = rootView.layer {
            let pillRect = rootView.bounds
            let pillPath = CGPath(roundedRect: pillRect,
                                  cornerWidth: pillRect.height / 2,
                                  cornerHeight: pillRect.height / 2,
                                  transform: nil)
            layer.shadowPath = pillPath
            layer.shadowColor = NSColor(white: 0, alpha: 0.15).cgColor
            layer.shadowOffset = CGSize(width: 0, height: -4)
            layer.shadowRadius = 24
            layer.shadowOpacity = 1
        }
    case "prod":
        break
    default:
        print("unknown variant")
    }
}

panel.orderFrontRegardless()
vc.switchToRecording()

DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
    let t = Process()
    t.launchPath = "/usr/sbin/screencapture"
    t.arguments = ["-x", "-D", "1", "/tmp/f6-\(variant).png"]
    try? t.run(); t.waitUntilExit()
    print("[F6-prod] saved /tmp/f6-\(variant).png")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        NSApp.terminate(nil)
    }
}

app.run()
