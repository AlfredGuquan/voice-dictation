// Tracer: Text injection via clipboard paste (proven reliable method)
import Cocoa
import Foundation

func injectViaClipboard(_ text: String) {
    let pasteboard = NSPasteboard.general
    let oldContents = pasteboard.string(forType: .string)

    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)

    // Simulate Cmd+V
    let source = CGEventSource(stateID: .combinedSessionState)
    let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
    let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
    cmdDown?.flags = .maskCommand
    cmdUp?.flags = .maskCommand
    cmdDown?.post(tap: .cghidEventTap)
    cmdUp?.post(tap: .cghidEventTap)

    usleep(200_000)
    if let old = oldContents {
        pasteboard.clearContents()
        pasteboard.setString(old, forType: .string)
    }
}

// TextEdit should already be focused
let testText = "语音听写测试：Hello World！这段文字通过剪贴板注入，支持中英文混合。"
print("[INJECT] Injecting: \(testText)")
injectViaClipboard(testText)
print("[INJECT] Done.")
