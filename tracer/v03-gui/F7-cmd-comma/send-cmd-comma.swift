// Post a genuine Cmd+, CGEvent (keyCode 43 = comma, flags = cmd)
import Cocoa
let src = CGEventSource(stateID: .hidSystemState)
// key down
let down = CGEvent(keyboardEventSource: src, virtualKey: 0x2B, keyDown: true)
down?.flags = .maskCommand
down?.post(tap: .cghidEventTap)
// key up
let up = CGEvent(keyboardEventSource: src, virtualKey: 0x2B, keyDown: false)
up?.flags = .maskCommand
up?.post(tap: .cghidEventTap)
print("posted Cmd+,")
