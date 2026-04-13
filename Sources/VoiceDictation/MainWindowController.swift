import Cocoa
import SwiftUI

/// Manages the main application window (NSWindow hosting SwiftUI content).
/// Designed as a singleton toggled from the menu bar.
final class MainWindowController {
    private var window: NSWindow?
    private let historyStore: HistoryStore
    private let vocabularyStore: VocabularyStore

    init(historyStore: HistoryStore, vocabularyStore: VocabularyStore) {
        self.historyStore = historyStore
        self.vocabularyStore = vocabularyStore
    }

    /// Toggle the main window: show if hidden, bring to front if visible.
    func toggleWindow() {
        if let window = window, window.isVisible {
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
        } else {
            showWindow()
        }
    }

    /// Show the main window, creating it if needed.
    func showWindow() {
        if window == nil {
            createWindow()
        }
        guard let window = window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Private

    private func createWindow() {
        let contentView = MainContentView(
            historyStore: historyStore,
            vocabularyStore: vocabularyStore
        )

        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 850, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Voice Dictation"
        window.contentView = hostingView
        window.minSize = NSSize(width: 700, height: 400)
        window.center()
        window.isReleasedWhenClosed = false  // Keep window object alive after close
        window.tabbingMode = .disallowed

        // Set window background to match theme
        window.backgroundColor = NSColor(red: 245/255, green: 240/255, blue: 232/255, alpha: 1.0)

        self.window = window
    }
}
