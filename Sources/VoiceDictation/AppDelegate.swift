import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let pipeline = DictationPipeline()
    private var statusItem: NSStatusItem?
    private var mainWindowController: MainWindowController?
    private var hotkeyStatusMenuItem: NSMenuItem?
    private var openWindowHotkeyStatusMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar icon
        setupStatusItem()

        // Prepare main window controller (uses pipeline's stores)
        // History-list retry routes through clipboard since the user is
        // already inside the main window — focus has left the original app.
        mainWindowController = MainWindowController(
            historyStore: pipeline.historyStore,
            vocabularyStore: pipeline.vocabularyStore,
            onRetryRecord: { [weak self] record in
                Task { @MainActor [weak self] in
                    self?.pipeline.retry(record: record, output: .clipboard)
                }
            }
        )

        // Application menu lets Cmd+, reach Settings when main window is frontmost.
        // Without NSApp.mainMenu, status-item menu keyEquivalents only fire on popup.
        setupMainMenu()

        // Keep the status-item hint label in sync with the active hotkey.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshHotkeyStatusLabel),
            name: .hotkeyConfigChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshOpenWindowHotkey),
            name: .openWindowHotkeyChanged,
            object: nil
        )

        // Start the dictation pipeline
        pipeline.start()
        refreshHotkeyStatusLabel()
        registerOpenWindowHotkey()
    }

    @objc private func refreshOpenWindowHotkey() {
        registerOpenWindowHotkey()
        refreshOpenWindowHotkeyLabel()
    }

    private func registerOpenWindowHotkey() {
        if let chord = Config.openWindowHotkey {
            GlobalShortcuts.shared.register(chord: chord) { [weak self] in
                self?.mainWindowController?.toggleWindow()
            }
        } else {
            GlobalShortcuts.shared.unregister()
        }
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
            keyEquivalent: ""
        )
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
        hotkeyStatusMenuItem = statusMenuItem

        let openWindowItemLabel = NSMenuItem(
            title: "开窗快捷键：未设置",
            action: nil,
            keyEquivalent: ""
        )
        openWindowItemLabel.isEnabled = false
        menu.addItem(openWindowItemLabel)
        openWindowHotkeyStatusMenuItem = openWindowItemLabel

        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        )

        statusItem?.menu = menu

        refreshOpenWindowHotkeyLabel()
    }

    @objc private func openMainWindow() {
        mainWindowController?.toggleWindow()
    }

    @objc private func refreshHotkeyStatusLabel() {
        let name = Config.hotkey.displayName
        hotkeyStatusMenuItem?.title = "Press \(name) to dictate"
    }

    private func refreshOpenWindowHotkeyLabel() {
        if let hotkey = Config.openWindowHotkey {
            openWindowHotkeyStatusMenuItem?.title = "开窗快捷键：\(hotkey.displayName)"
        } else {
            openWindowHotkeyStatusMenuItem?.title = "开窗快捷键：未设置（点设置配置）"
        }
    }

    @objc private func openSettings() {
        mainWindowController?.showSettings()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // Application menu (first item's submenu is treated as the app menu).
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu(title: "Voice Dictation")

        let prefItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        prefItem.keyEquivalentModifierMask = [.command]
        prefItem.target = self
        appMenu.addItem(prefItem)

        appMenu.addItem(NSMenuItem.separator())

        appMenu.addItem(
            NSMenuItem(
                title: "Quit Voice Dictation",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        appMenuItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }
}
