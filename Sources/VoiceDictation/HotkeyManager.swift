import Cocoa
import Carbon.HIToolbox

/// Configurable global hotkey via CGEvent tap.
///
/// Two modes coexist — selected by HotkeyType:
///   - `.singleModifier(keyCode:)`   — "hold to talk"  (flagsChanged driven)
///   - `.chord(keyCode:, modifiers:)` — "press to toggle" (keyDown driven)
///
/// The same event tap masks `flagsChanged | keyDown` and dispatches per the
/// currently active HotkeyType. Changing the hotkey at runtime calls
/// `reload(to:)` which only swaps the dispatch target — the tap itself is
/// not recreated (cheap + no dropped events).
final class HotkeyManager {
    enum HotkeyEvent {
        /// Single-modifier key went down. Pipeline should start recording.
        case singleModifierDown
        /// Single-modifier key went up. Pipeline should stop + process.
        case singleModifierUp
        /// Chord pressed (toggle semantics). Pipeline flips recording state.
        case comboPress
        /// Esc pressed while recording. Pipeline should cancel.
        case cancel
    }

    /// Hotkey descriptor persisted via Config/UserDefaults.
    enum HotkeyType: Equatable, Codable {
        /// Single modifier key, e.g. right Option (61), Fn (63), CapsLock (57).
        case singleModifier(keyCode: Int64)
        /// Chord: keyCode + modifier mask (CGEventFlags raw value).
        case chord(keyCode: Int64, modifiers: UInt64)

        /// Human-readable form for UI ("right ⌥", "⌃Space", ...).
        var displayName: String {
            switch self {
            case .singleModifier(let kc):
                return HotkeyManager.singleModifierName(keyCode: kc)
            case .chord(let kc, let mods):
                let flags = CGEventFlags(rawValue: mods)
                let modPart = HotkeyManager.modifierSymbols(flags: flags)
                let keyPart = HotkeyManager.chordKeyName(keyCode: kc)
                return modPart + keyPart
            }
        }
    }

    /// Known-conflict hint. Used by Settings to show warning text.
    struct KnownConflict {
        let keyCode: Int64
        let modifiers: UInt64
        let description: String
    }

    /// Best-effort static list of known-occupied shortcuts.
    /// Not exhaustive — third-party apps (Alfred, Raycast, ...) aren't in any
    /// queryable API. We only warn, never block (spec F9: "只提示不拦截").
    static let knownConflicts: [KnownConflict] = [
        // Command-based system shortcuts
        KnownConflict(keyCode: 49, modifiers: CGEventFlags.maskCommand.rawValue,
                      description: "Spotlight 搜索"),
        KnownConflict(keyCode: 49,
                      modifiers: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue,
                      description: "Finder 搜索"),
        KnownConflict(keyCode: 48, modifiers: CGEventFlags.maskCommand.rawValue,
                      description: "App 切换"),
        KnownConflict(keyCode: 48,
                      modifiers: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue,
                      description: "App 反向切换"),
        KnownConflict(keyCode: 23, // Cmd+Shift+5 (5 keyCode = 23)
                      modifiers: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue,
                      description: "截图工具栏"),
        KnownConflict(keyCode: 20, // Cmd+Shift+3
                      modifiers: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue,
                      description: "截图全屏"),
        KnownConflict(keyCode: 21, // Cmd+Shift+4
                      modifiers: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue,
                      description: "截图选区"),
        KnownConflict(keyCode: 49, modifiers: CGEventFlags.maskControl.rawValue,
                      description: "输入法切换（某些配置）"),
        // macOS built-in dictation hotkey default = Fn Fn; too subtle to detect — skip.
    ]

    /// Look up a known conflict for a proposed hotkey. Returns nil if unknown.
    static func conflictDescription(for hotkey: HotkeyType) -> String? {
        switch hotkey {
        case .singleModifier:
            return nil  // no system defaults on bare modifier keys
        case .chord(let kc, let mods):
            return knownConflicts.first { $0.keyCode == kc && $0.modifiers == mods }?.description
        }
    }

    // MARK: - Public API

    var onEvent: ((HotkeyEvent) -> Void)?

    /// Set to true when recording is active — Esc is only intercepted during recording.
    var isActive = false

    private(set) var currentHotkey: HotkeyType

    init(hotkey: HotkeyType = .singleModifier(keyCode: 61)) {
        self.currentHotkey = hotkey
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isModifierDown = false

    func start() -> Bool {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[HotkeyManager] Failed to create event tap — Accessibility permission missing")
            return false
        }

        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[HotkeyManager] Event tap active with \(currentHotkey.displayName)")
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isModifierDown = false
    }

    /// Swap the active hotkey at runtime. Must be called on main thread.
    ///
    /// Safety: the event tap is NOT recreated — it still masks
    /// flagsChanged|keyDown which covers both modes. Only the dispatch
    /// target (currentHotkey) is replaced, atomically in the main
    /// thread, while the callback also dispatches to main. `isModifierDown`
    /// is reset so a stale "key is down" flag from the old single-modifier
    /// binding can't leak into the new binding.
    func reload(to newHotkey: HotkeyType) {
        assert(Thread.isMainThread, "HotkeyManager.reload must be called on main thread")
        guard newHotkey != currentHotkey else { return }
        isModifierDown = false
        currentHotkey = newHotkey
        print("[HotkeyManager] reloaded to \(newHotkey.displayName)")
    }

    // MARK: - Event dispatch

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // Handle tap disabled (system can disable under load)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Esc (keyCode 53) — cancel only while recording; otherwise pass through
        if type == .keyDown && keyCode == 53 && isActive {
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?(.cancel)
            }
            return nil
        }

        let modifierMask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        let pressedModifiers = event.flags.intersection(modifierMask)

        switch currentHotkey {
        case .singleModifier(let target):
            guard type == .flagsChanged, keyCode == target else {
                return Unmanaged.passUnretained(event)
            }
            let targetFlag = Self.modifierFlag(forSingleModifierKeyCode: target)
            // When the modifier is held alone, intersection equals its own flag.
            // For modifier-less keys (CapsLock=57, Fn=63) targetFlag == [], so
            // the "held" state must be derived differently.
            let isNowDown: Bool
            if targetFlag == [] {
                // CapsLock / Fn — no modifier flag to check. Fall back to
                // flipping isModifierDown each flagsChanged event for this
                // keyCode (CapsLock / Fn emit one flagsChanged per toggle).
                isNowDown = !isModifierDown
            } else {
                isNowDown = (pressedModifiers == targetFlag)
            }

            if isNowDown {
                if !isModifierDown {
                    isModifierDown = true
                    DispatchQueue.main.async { [weak self] in
                        self?.onEvent?(.singleModifierDown)
                    }
                }
            } else {
                if isModifierDown {
                    isModifierDown = false
                    DispatchQueue.main.async { [weak self] in
                        self?.onEvent?(.singleModifierUp)
                    }
                }
            }
            return nil  // swallow the modifier flagsChanged

        case .chord(let target, let mods):
            guard type == .keyDown, keyCode == target else {
                return Unmanaged.passUnretained(event)
            }
            if pressedModifiers.rawValue == mods {
                DispatchQueue.main.async { [weak self] in
                    self?.onEvent?(.comboPress)
                }
                return nil  // swallow matching chord
            }
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - Display helpers

    /// The CGEventFlags bit that a held-alone single modifier sets in `flags`.
    /// Returns `[]` for CapsLock (57) / Fn (63) — those produce a flagsChanged
    /// event but do not contribute a bit in the modifier mask we care about.
    static func modifierFlag(forSingleModifierKeyCode keyCode: Int64) -> CGEventFlags {
        switch keyCode {
        case 61, 58: return .maskAlternate  // right/left Option
        case 59, 62: return .maskControl    // left/right Control
        case 60, 56: return .maskShift      // right/left Shift
        case 54, 55: return .maskCommand    // right/left Command
        default:
            return []  // CapsLock (57), Fn (63), others
        }
    }

    static func singleModifierName(keyCode: Int64) -> String {
        switch keyCode {
        case 54: return "right ⌘"
        case 55: return "left ⌘"
        case 56: return "left ⇧"
        case 60: return "right ⇧"
        case 58: return "left ⌥"
        case 61: return "right ⌥"
        case 59: return "left ⌃"
        case 62: return "right ⌃"
        case 57: return "⇪ CapsLock"
        case 63: return "fn"
        default: return "key \(keyCode)"
        }
    }

    static func modifierSymbols(flags: CGEventFlags) -> String {
        var s = ""
        if flags.contains(.maskControl)   { s += "⌃" }
        if flags.contains(.maskAlternate) { s += "⌥" }
        if flags.contains(.maskShift)     { s += "⇧" }
        if flags.contains(.maskCommand)   { s += "⌘" }
        return s
    }

    static func chordKeyName(keyCode: Int64) -> String {
        // Key codes from Carbon/HIToolbox/Events.h — covers most common chord keys.
        switch keyCode {
        case 49: return "Space"
        case 53: return "Esc"
        case 36: return "Return"
        case 48: return "Tab"
        case 51: return "Delete"
        case 117: return "Fwd-Delete"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 0:  return "A"
        case 1:  return "S"
        case 2:  return "D"
        case 3:  return "F"
        case 4:  return "H"
        case 5:  return "G"
        case 6:  return "Z"
        case 7:  return "X"
        case 8:  return "C"
        case 9:  return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 41: return ";"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 50: return "`"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 25: return "9"
        case 26: return "7"
        case 28: return "8"
        case 29: return "0"
        case 27: return "-"
        case 24: return "="
        case 33: return "["
        case 30: return "]"
        case 39: return "'"
        case 42: return "\\"
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default: return "key\(keyCode)"
        }
    }

    /// Classify a user key press (via NSEvent / CGEvent) into a HotkeyType.
    /// - If `keyCode` is a known lone-modifier key and flags are empty/only that
    ///   modifier, returns `.singleModifier`.
    /// - Otherwise returns `.chord` with the pressed non-empty modifier mask.
    ///   Returns nil when flags are empty on a non-modifier key (plain letter —
    ///   we require at least one modifier for chords so it doesn't capture
    ///   every keystroke).
    static func classify(keyCode: Int64, flags: CGEventFlags) -> HotkeyType? {
        let mask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        let pressed = flags.intersection(mask)

        let isLoneModifier: Bool
        switch keyCode {
        case 54, 55, 56, 60, 58, 61, 59, 62, 57, 63:
            isLoneModifier = true
        default:
            isLoneModifier = false
        }

        if isLoneModifier {
            // Accept only when no *other* modifier is down. (e.g. pressing
            // Shift+right-Option should not record "right Option" alone.)
            let own = modifierFlag(forSingleModifierKeyCode: keyCode)
            if pressed == own {
                return .singleModifier(keyCode: keyCode)
            }
            return nil
        }

        // Non-modifier key — requires at least one modifier to be a valid chord.
        if pressed.isEmpty { return nil }
        return .chord(keyCode: keyCode, modifiers: pressed.rawValue)
    }
}
