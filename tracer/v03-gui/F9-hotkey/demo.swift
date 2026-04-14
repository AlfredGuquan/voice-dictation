// F9 tracer: dual-mode CGEventTap (flagsChanged + keyDown in same tap)
// Run: swift tracer/v03-gui/F9-hotkey/demo.swift
//
// Verifies:
// 1. A single CGEventTap with mask = (flagsChanged | keyDown) receives both event types.
// 2. Single-modifier "hold-to-talk" mode: right Option (keyCode 61) — flagsChanged only.
// 3. Combo-key "press-to-toggle" mode: Ctrl+Space (keyCode 49 + maskControl) — keyDown only.
// 4. Both modes can be armed simultaneously.
// 5. Conflict detection: try RegisterEventHotKey (Carbon) to probe system-reserved combos.

import Cocoa
import Carbon.HIToolbox

enum HotkeyMode {
    case singleModifier(keyCode: Int64, modifier: CGEventFlags)
    case combo(keyCode: Int64, modifiers: CGEventFlags)
}

final class DualModeHotkey {
    var tap: CFMachPort?
    var src: CFRunLoopSource?
    var singleMode: HotkeyMode?
    var comboMode: HotkeyMode?
    var isModDown = false
    var onEvent: ((String) -> Void)?

    func start(single: HotkeyMode?, combo: HotkeyMode?) -> Bool {
        singleMode = single
        comboMode = combo
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { (_, type, event, ptr) -> Unmanaged<CGEvent>? in
                let me = Unmanaged<DualModeHotkey>.fromOpaque(ptr!).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        tap = t
        src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let mods: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        let pressed = event.flags.intersection(mods)

        // SINGLE-MODIFIER MODE (flagsChanged)
        if type == .flagsChanged, case let .singleModifier(targetCode, targetMod) = singleMode ?? .singleModifier(keyCode: -1, modifier: []) {
            if keyCode == targetCode {
                if pressed == targetMod {
                    if !isModDown { isModDown = true; onEvent?("[single] \(targetCode) DOWN") }
                } else {
                    if isModDown { isModDown = false; onEvent?("[single] \(targetCode) UP") }
                }
                return nil
            }
        }

        // COMBO MODE (keyDown)
        if type == .keyDown, case let .combo(targetCode, targetMods) = comboMode ?? .combo(keyCode: -1, modifiers: []) {
            if keyCode == targetCode && pressed == targetMods {
                onEvent?("[combo] \(targetCode)+\(targetMods.rawValue) PRESS")
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }

    func stop() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = src { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil; src = nil
    }
}

// --- Conflict probing: RegisterEventHotKey returns err if taken

func probeConflict(keyCode: UInt32, modifiers: UInt32) -> String {
    var hotKeyRef: EventHotKeyRef?
    let hotKeyID = EventHotKeyID(signature: OSType(0x46394B59), id: UInt32.random(in: 1...10000)) // 'F9KY'
    let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    if status == noErr {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        return "available (OSStatus=\(status))"
    }
    // -9868 = eventHotKeyExistsErr (system-level or another app registered)
    return "TAKEN (OSStatus=\(status))"
}

// ---- MAIN ----

let arg = CommandLine.arguments.dropFirst().first ?? "run"

if arg == "probe" {
    // Probe a set of common system combos; no event tap needed
    print("=== Carbon RegisterEventHotKey conflict probe ===")
    let combos: [(String, UInt32, UInt32)] = [
        ("Cmd+Space (Spotlight)",   UInt32(kVK_Space),    UInt32(cmdKey)),
        ("Ctrl+Space",              UInt32(kVK_Space),    UInt32(controlKey)),
        ("Cmd+Shift+D",             UInt32(kVK_ANSI_D),   UInt32(cmdKey | shiftKey)),
        ("Cmd+Shift+5 (screenshot)",UInt32(kVK_ANSI_5),   UInt32(cmdKey | shiftKey)),
        ("Cmd+Tab (switcher)",      UInt32(kVK_Tab),      UInt32(cmdKey)),
        ("F5 (dictation)",          UInt32(kVK_F5),       0),
        ("Right Option alone",      UInt32(kVK_RightOption), 0),
    ]
    for (name, key, mod) in combos {
        print("  \(name.padding(toLength: 32, withPad: " ", startingAt: 0)) → \(probeConflict(keyCode: key, modifiers: mod))")
    }
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let hk = DualModeHotkey()
hk.onEvent = { msg in
    print("EVENT:", msg)
}

// Arm both modes: right Option (keyCode 61) + Ctrl+Space (49, ctrl)
let ok = hk.start(
    single: .singleModifier(keyCode: 61, modifier: .maskAlternate),
    combo: .combo(keyCode: 49, modifiers: .maskControl)
)
if !ok {
    print("[F9] failed to create event tap — need Accessibility permission")
    exit(1)
}
print("[F9] dual-mode armed. Press right Option (hold) or Ctrl+Space. Auto-exit in 8s.")

// Synthesize a combo press after 1s (so we can observe keyDown path without manual input)
// Note: synthesizing via CGEventPost may loop through our own tap; expected.
DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
    print("[F9] synthesizing Ctrl+Space keyDown...")
    let src = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: src, virtualKey: 0x31, keyDown: true)
    down?.flags = .maskControl
    down?.post(tap: .cghidEventTap)
    let up = CGEvent(keyboardEventSource: src, virtualKey: 0x31, keyDown: false)
    up?.flags = .maskControl
    up?.post(tap: .cghidEventTap)
}

// Synthesize right Option press (flagsChanged) after 2s
DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
    print("[F9] synthesizing right Option down/up...")
    let src = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: src, virtualKey: 0x3D, keyDown: true)
    down?.flags = .maskAlternate
    down?.type = .flagsChanged
    down?.post(tap: .cghidEventTap)
    let up = CGEvent(keyboardEventSource: src, virtualKey: 0x3D, keyDown: false)
    up?.flags = []
    up?.type = .flagsChanged
    up?.post(tap: .cghidEventTap)
}

DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
    hk.stop()
    print("[F9] done")
    NSApp.terminate(nil)
}

app.run()
