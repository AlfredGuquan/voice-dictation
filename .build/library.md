# Voice Dictation - Library Knowledge

## AXUIElement casting
- `AXUIElementCopyAttributeValue` returns `AnyObject?`. The Swift compiler treats `as? AXUIElement` as always succeeding (CoreFoundation toll-free bridging), so it errors.
- Correct pattern: validate with `CFGetTypeID(obj) == AXUIElementGetTypeID()` then force-cast.

## CGEvent tap memory management
- Event tap callbacks return `Unmanaged<CGEvent>?`. For events being passed through unchanged, use `passUnretained`. Using `passRetained` leaks every event.
- For swallowed events, return `nil`.

## CGEventFlags modifier matching
- `flags.contains(.maskAlternate)` is a subset check -- matches any combo containing Option.
- For exact-modifier matching: `event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl]) == .maskAlternate`.

## osascript string injection
- `display notification` AppleScript takes quoted strings. User-provided text (error messages, API responses) can contain quotes that break or inject commands.
- Escape both backslashes and double-quotes before interpolation into osascript strings.

## SwiftUI onReceive for external state
- `VocabularyStore` is not an `ObservableObject`. To react to external file changes in SwiftUI, use `onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))` to reload state on app activation.
- Requires `import Combine` for `NotificationCenter.default.publisher(for:)`.

## FloatingPillPanel.create()
- Returns `FloatingPillPanel?` (optional). Callers must `guard let` the result.
- Returns nil when `NSScreen.main` is nil (e.g., headless, all displays disconnected).
