import Cocoa
import Carbon.HIToolbox

/// Global keyboard chord shortcuts via Carbon `RegisterEventHotKey`.
///
/// Independent of the dictation `HotkeyManager` (which uses a CGEventTap so it
/// can intercept lone modifier keys). For simple "press chord → fire handler"
/// shortcuts (e.g. open main window) Carbon is lighter and the standard macOS
/// path — Alfred / Raycast / Things all use it.
///
/// This class exposes a single named slot — register a new chord and the prior
/// one is unregistered. Multiple distinct chords would need an id-keyed map;
/// we don't need that yet.
final class GlobalShortcuts {
    static let shared = GlobalShortcuts()

    private init() {}

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var handler: (() -> Void)?

    /// Carbon four-byte signature — purely for tag/debug, must be stable.
    private static let signature: OSType = {
        let bytes: [UInt8] = [0x56, 0x4F, 0x49, 0x54]  // "VOIT"
        return OSType(bytes[0]) << 24
            | OSType(bytes[1]) << 16
            | OSType(bytes[2]) << 8
            | OSType(bytes[3])
    }()

    /// Register a chord and bind its press to `handler`. Replaces any prior
    /// registration. Single-modifier chords are rejected — those are the
    /// dictation hotkey's territory and would conflict.
    func register(chord: HotkeyManager.HotkeyType, handler: @escaping () -> Void) {
        unregister()

        guard case .chord(let keyCode, let modifiers) = chord else {
            print("[GlobalShortcuts] refused non-chord hotkey: \(chord.displayName)")
            return
        }

        self.handler = handler

        // CGEventFlags rawValue → Carbon modifier flags (different bit layout).
        let cg = CGEventFlags(rawValue: modifiers)
        var carbonMods: UInt32 = 0
        if cg.contains(.maskCommand)   { carbonMods |= UInt32(cmdKey) }
        if cg.contains(.maskShift)     { carbonMods |= UInt32(shiftKey) }
        if cg.contains(.maskAlternate) { carbonMods |= UInt32(optionKey) }
        if cg.contains(.maskControl)   { carbonMods |= UInt32(controlKey) }

        let hkid = EventHotKeyID(signature: Self.signature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            carbonMods,
            hkid,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let validRef = ref else {
            print("[GlobalShortcuts] RegisterEventHotKey failed (status=\(status)) for \(chord.displayName)")
            self.handler = nil
            return
        }
        self.hotKeyRef = validRef

        if handlerRef == nil {
            installHandler()
        }

        print("[GlobalShortcuts] registered \(chord.displayName)")
    }

    /// Unregister the current chord. Safe to call when nothing is registered.
    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        handler = nil
    }

    private func installHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var ref: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let me = Unmanaged<GlobalShortcuts>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    me.handler?()
                }
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &ref
        )
        if status == noErr {
            handlerRef = ref
        } else {
            print("[GlobalShortcuts] InstallEventHandler failed: \(status)")
        }
    }
}
