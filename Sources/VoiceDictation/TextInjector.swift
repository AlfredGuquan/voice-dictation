import Cocoa
import Foundation

/// Injects text at the current cursor position using the clipboard paste method.
/// Saves/restores the user's clipboard content.
final class TextInjector {

    /// Check if there's a focused text field that can accept input.
    /// Uses Accessibility API to detect the focused element.
    static func hasFocusedTextField() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: AnyObject?
        let appResult = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp
        )
        guard appResult == .success, let app = focusedApp else {
            return false
        }

        var focusedElement: AnyObject?
        let elemResult = AXUIElementCopyAttributeValue(
            app as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement
        )
        guard elemResult == .success, let element = focusedElement else {
            return false
        }

        // Check if the focused element has a value attribute (text field indicator)
        var role: AnyObject?
        AXUIElementCopyAttributeValue(
            element as! AXUIElement, kAXRoleAttribute as CFString, &role
        )
        if let roleStr = role as? String {
            let textRoles = [
                kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole,
                "AXWebArea",  // Web text inputs
            ]
            return textRoles.contains(roleStr)
        }
        return false
    }

    /// Inject text at the current cursor position.
    /// Returns true if text was pasted into a text field, false if only copied to clipboard.
    @discardableResult
    static func inject(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general

        // Save current clipboard content
        let oldTypes = pasteboard.types
        var oldItems: [(NSPasteboard.PasteboardType, Data)] = []
        if let types = oldTypes {
            for type in types {
                if let data = pasteboard.data(forType: type) {
                    oldItems.append((type, data))
                }
            }
        }

        // Write our text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let hasFocus = hasFocusedTextField()

        if hasFocus {
            // Simulate Cmd+V
            simulatePaste()

            // Wait for paste to complete, then restore clipboard
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                restoreClipboard(items: oldItems)
            }
            return true
        } else {
            // No text field focused — leave text in clipboard, send notification
            sendNotification(
                title: "Voice Dictation",
                body: "已复制到剪贴板"
            )
            return false
        }
    }

    private static func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)

        // Cmd+V: keyCode 0x09 = 'v'
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        cmdDown?.flags = .maskCommand
        cmdUp?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
    }

    private static func restoreClipboard(items: [(NSPasteboard.PasteboardType, Data)]) {
        guard !items.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        for (type, data) in items {
            pasteboard.setData(data, forType: type)
        }
    }

    private static func sendNotification(title: String, body: String) {
        // Use NSUserNotification for simplicity (deprecated but works without entitlements)
        // In a production app, use UNUserNotificationCenter
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = [
            "-e",
            "display notification \"\(body)\" with title \"\(title)\"",
        ]
        try? task.run()
    }
}
