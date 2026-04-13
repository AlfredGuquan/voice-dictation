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
        guard appResult == .success, let focusedAppObj = focusedApp else {
            return false
        }
        // Validate the returned object is actually an AXUIElement
        guard CFGetTypeID(focusedAppObj) == AXUIElementGetTypeID() else {
            return false
        }
        let app = focusedAppObj as! AXUIElement

        var focusedElement: AnyObject?
        let elemResult = AXUIElementCopyAttributeValue(
            app, kAXFocusedUIElementAttribute as CFString, &focusedElement
        )
        guard elemResult == .success, let focusedElemObj = focusedElement else {
            return false
        }
        guard CFGetTypeID(focusedElemObj) == AXUIElementGetTypeID() else {
            return false
        }
        let element = focusedElemObj as! AXUIElement

        // Check if the focused element has a value attribute (text field indicator)
        var role: AnyObject?
        AXUIElementCopyAttributeValue(
            element, kAXRoleAttribute as CFString, &role
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
        // Check focus BEFORE touching clipboard to avoid losing content
        let hasFocus = hasFocusedTextField()

        if hasFocus {
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
            // Simulate Cmd+V
            simulatePaste()

            // Wait for paste to complete, then restore clipboard
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                restoreClipboard(items: oldItems)
            }
            return true
        } else {
            // No text field focused — copy text to clipboard, send notification
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
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
        let escapedBody = body
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedTitle = title
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = [
            "-e",
            "display notification \"\(escapedBody)\" with title \"\(escapedTitle)\"",
        ]
        try? task.run()
    }
}
