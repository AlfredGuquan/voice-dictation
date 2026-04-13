// Tracer: System-wide text injection via CGEvents
// Proves: Can inject text into any focused text field
import Cocoa
import Foundation

func injectText(_ text: String) {
    // Use CGEvent to simulate keyboard input via Unicode string
    let source = CGEventSource(stateID: .combinedSessionState)

    for scalar in text.unicodeScalars {
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)

        keyDown?.keyboardSetUnicodeString(stringLength: 1, unicodeString: [UniChar(scalar.value)])
        keyUp?.keyboardSetUnicodeString(stringLength: 1, unicodeString: [UniChar(scalar.value)])

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // Small delay between characters for reliability
        usleep(5000) // 5ms
    }
}

// Alternative: clipboard-based injection (faster for long text)
func injectViaClipboard(_ text: String) {
    let pasteboard = NSPasteboard.general
    // Save current clipboard
    let oldContents = pasteboard.string(forType: .string)

    // Set new text
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)

    // Simulate Cmd+V
    let source = CGEventSource(stateID: .combinedSessionState)
    let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V key
    let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
    cmdDown?.flags = .maskCommand
    cmdUp?.flags = .maskCommand
    cmdDown?.post(tap: .cghidEventTap)
    cmdUp?.post(tap: .cghidEventTap)

    // Restore clipboard after a delay
    usleep(200_000) // 200ms
    if let old = oldContents {
        pasteboard.clearContents()
        pasteboard.setString(old, forType: .string)
    }
}

print("[INJECT] Waiting 3 seconds — focus a text field (TextEdit should be open)...")
Thread.sleep(forTimeInterval: 3)

let testText = "Hello 你好！Voice dictation test 语音听写测试。"
print("[INJECT] Injecting via CGEvent key simulation: \"\(testText)\"")
injectText(testText)

Thread.sleep(forTimeInterval: 1)

let testText2 = "\n[Clipboard method] 这是通过剪贴板注入的文字。"
print("[INJECT] Injecting via clipboard paste: \"\(testText2)\"")
injectViaClipboard(testText2)

print("[INJECT] Done. Check the focused text field.")
