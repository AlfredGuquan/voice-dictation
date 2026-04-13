// Tracer: Global hotkey registration (right Option key)
// Proves: CGEvent tap can intercept right Option key system-wide
import Cocoa

class HotkeyMonitor {
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    var isRecording = false

    func start() {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()

                // Right Option key = keyCode 61
                if event.getIntegerValueField(.keyboardEventKeycode) == 61 {
                    let flags = event.flags
                    if flags.contains(.maskAlternate) {
                        // Key down
                        if !monitor.isRecording {
                            monitor.isRecording = true
                            print("[HOTKEY] Right Option DOWN — recording started")
                        }
                    } else {
                        // Key up
                        if monitor.isRecording {
                            monitor.isRecording = false
                            print("[HOTKEY] Right Option UP — recording stopped")
                        }
                    }
                    // Swallow the event so it doesn't reach the app
                    return nil
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[HOTKEY] ERROR: Failed to create event tap. Check Accessibility permissions.")
            exit(1)
        }

        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[HOTKEY] Event tap active. Press Right Option key to test. Ctrl+C to exit.")
        print("[HOTKEY] Waiting 8 seconds for input...")
    }
}

let monitor = HotkeyMonitor()
monitor.start()

// Run for 8 seconds then exit
DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
    print("[HOTKEY] Test complete. Exiting.")
    CFRunLoopStop(CFRunLoopGetCurrent())
}
CFRunLoopRun()
