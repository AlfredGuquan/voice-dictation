// F7 tracer: reproduce Cmd+, bug where menu item on statusItem.menu doesn't open main window
// Run: swift tracer/v03-gui/F7-cmd-comma/demo.swift
//
// Verifies:
// 1. Without NSApp.mainMenu set, Cmd+, on a main window routes to first responder (NSTextField)
//    not the statusItem menu — opens "character insertion / text helper" popup instead.
// 2. Fix: build a proper NSApp.mainMenu with a "Preferences..." item that has keyEquivalent ",".
//    Alternative fix: register a local keyDown monitor on the window.

import Cocoa

let useFix = CommandLine.arguments.contains("--fix")

class Delegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var window: NSWindow?
    var settingsOpenCount = 0

    func applicationDidFinishLaunching(_ n: Notification) {
        // Status bar menu (mirrors production AppDelegate.swift:39-46)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.title = "F7"
        let menu = NSMenu()
        let pref = NSMenuItem(title: "打开主窗口", action: #selector(openMain), keyEquivalent: ",")
        pref.keyEquivalentModifierMask = [.command]
        pref.target = self
        menu.addItem(pref)
        statusItem?.menu = menu

        if useFix {
            // Fix: build a real NSApp.mainMenu so Cmd+, is captured before reaching first responder
            buildMainMenu()
        }

        // Create a main window with a text field focused
        createWindow()
        NSApp.activate(ignoringOtherApps: true)

        print("[F7] demo up — press Cmd+, inside the text field (which is focused)")
        print("[F7] fix=\(useFix). expected: settings action fires only when --fix.")
    }

    func buildMainMenu() {
        let main = NSMenu()
        let appMenuItem = NSMenuItem()
        main.addItem(appMenuItem)
        let appMenu = NSMenu()
        let prefItem = NSMenuItem(title: "Preferences...", action: #selector(openMain), keyEquivalent: ",")
        prefItem.keyEquivalentModifierMask = [.command]
        prefItem.target = self
        appMenu.addItem(prefItem)
        appMenuItem.submenu = appMenu
        NSApp.mainMenu = main
    }

    func createWindow() {
        let w = NSWindow(
            contentRect: NSRect(x: 100, y: 300, width: 500, height: 200),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "F7 Demo Main Window"
        let tf = NSTextField(frame: NSRect(x: 20, y: 100, width: 460, height: 30))
        tf.placeholderString = "focus here and press Cmd+,"
        tf.stringValue = ""
        w.contentView?.addSubview(tf)

        let status = NSTextField(labelWithString: "Cmd+, action fires: 0 times")
        status.frame = NSRect(x: 20, y: 40, width: 460, height: 20)
        status.tag = 99
        w.contentView?.addSubview(status)

        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(tf)
        self.window = w
    }

    @objc func openMain() {
        settingsOpenCount += 1
        if let status = window?.contentView?.viewWithTag(99) as? NSTextField {
            status.stringValue = "Cmd+, action fires: \(settingsOpenCount) times"
        }
        print("[F7] openMain() fired — count=\(settingsOpenCount)")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let d = Delegate()
app.delegate = d
app.run()
