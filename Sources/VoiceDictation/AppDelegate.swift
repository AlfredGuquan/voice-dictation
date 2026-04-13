import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let pipeline = DictationPipeline()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar icon
        setupStatusItem()

        // Start the dictation pipeline
        pipeline.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Keep running as menu bar app
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "mic.fill",
                accessibilityDescription: "Voice Dictation"
            )
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Voice Dictation", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let statusMenuItem = NSMenuItem(
            title: "Press Right Option to dictate",
            action: nil,
            keyEquivalent: ""
        )
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        )

        statusItem?.menu = menu
    }
}
