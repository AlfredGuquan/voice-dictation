import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let pipeline = DictationPipeline()
    private var statusItem: NSStatusItem?
    private var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar icon
        setupStatusItem()

        // Prepare main window controller (uses pipeline's stores)
        mainWindowController = MainWindowController(
            historyStore: pipeline.historyStore,
            vocabularyStore: pipeline.vocabularyStore
        )

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

        let openWindowItem = NSMenuItem(
            title: "打开主窗口",
            action: #selector(openMainWindow),
            keyEquivalent: ","
        )
        openWindowItem.keyEquivalentModifierMask = [.command]
        openWindowItem.target = self
        menu.addItem(openWindowItem)

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

    @objc private func openMainWindow() {
        mainWindowController?.toggleWindow()
    }
}
