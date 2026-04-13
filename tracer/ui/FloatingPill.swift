import Cocoa

// Custom NSPanel subclass that never becomes key window
class FloatingPillPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// --- App setup ---
let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // No Dock icon, no app switcher entry

// --- Screen geometry ---
guard let screen = NSScreen.main else { exit(1) }
let screenFrame = screen.visibleFrame
let panelWidth: CGFloat = 300
let panelHeight: CGFloat = 50
let panelX = screenFrame.midX - panelWidth / 2
let panelY = screenFrame.minY + 40  // 40pt above bottom edge

// --- Create the panel ---
let panel = FloatingPillPanel(
    contentRect: NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight),
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

// --- Pill-shaped content view ---
let contentView = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
contentView.wantsLayer = true
contentView.layer?.cornerRadius = panelHeight / 2
contentView.layer?.masksToBounds = true
contentView.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.85).cgColor

// --- Label ---
let label = NSTextField(frame: NSRect(x: 20, y: 0, width: panelWidth - 40, height: panelHeight))
label.stringValue = "🎤  Listening…"
label.isEditable = false
label.isBordered = false
label.isSelectable = false
label.backgroundColor = .clear
label.textColor = .white
label.font = NSFont.systemFont(ofSize: 16, weight: .medium)
label.alignment = .center
// Vertically center
label.cell?.wraps = false
label.cell?.isScrollable = false

contentView.addSubview(label)
panel.contentView = contentView

// --- Show without activating ---
panel.orderFrontRegardless()

// --- Auto-dismiss after 5 seconds ---
DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
    panel.close()
    app.terminate(nil)
}

// --- Run the event loop ---
app.run()
