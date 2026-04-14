import Cocoa

/// Custom NSPanel for in-app toasts — never becomes key or main window.
/// Required because toast content (error toast's close button) can receive clicks,
/// and vanilla NSPanel would promote to key on click, stealing focus from the
/// user's active text field (see CLAUDE.md: floating pill panel guidance).
final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
