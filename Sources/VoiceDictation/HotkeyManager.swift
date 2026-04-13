import Cocoa
import Carbon.HIToolbox

/// Manages global hotkey (right Option) and Esc key via CGEvent tap.
final class HotkeyManager {
    enum HotkeyEvent {
        case toggleRecording  // Right Option pressed
        case cancel           // Esc pressed
    }

    var onEvent: ((HotkeyEvent) -> Void)?

    /// Set to true when recording is active — Esc is only intercepted during recording.
    var isActive = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRightOptionDown = false

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
        print("[HotkeyManager] Event tap active")
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
    }

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // Handle tap disabled (system can disable it under load)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Right Option key (keyCode 61)
        if type == .flagsChanged && keyCode == 61 {
            let flags = event.flags
            if flags.contains(.maskAlternate) {
                // Key down
                if !isRightOptionDown {
                    isRightOptionDown = true
                    DispatchQueue.main.async { [weak self] in
                        self?.onEvent?(.toggleRecording)
                    }
                }
            } else {
                // Key up
                isRightOptionDown = false
            }
            // Swallow the event
            return nil
        }

        // Esc key (keyCode 53) — only intercept when actively recording
        if type == .keyDown && keyCode == 53 && isActive {
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?(.cancel)
            }
            // Swallow Esc during recording
            return nil
        }

        return Unmanaged.passRetained(event)
    }
}
