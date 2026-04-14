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
- Default size is now `232x40` (v0.3 design) with `hasShadow = false`; shadow is drawn
  by `PillViewController` on its root `view.layer` using an explicit `shadowPath`.

## CALayer shadow on rounded views (F6 gotcha)
- `view.layer.shadowRadius/Offset/Opacity` alone draws the shadow using `layer.bounds`
  as the caster shape. For a rounded-corner content (pill / capsule / rounded card)
  this leaks a **rectangular halo** visible on light backgrounds.
- Fix: set `layer.shadowPath = CGPath(roundedRect: view.bounds, cornerWidth: r, cornerHeight: r, transform: nil)`
  and keep it in sync from `viewDidLayout()` when bounds may change.
- Do NOT mix `view.shadow = NSShadow()` with `layer.shadow*` — they draw via two different
  paths (AppKit drawRect vs CA) and stack/desync.
- Also disable `NSPanel.hasShadow` if the content layer already draws a shadowPath —
  otherwise the system window shadow overlaps as a separate rect halo.

## Progress bar trickle animation (F11)
- Use chained `NSAnimationContext.runAnimationGroup` with custom `timingFunction`
  (`CAMediaTimingFunction(controlPoints:)`) rather than `Timer`+manual frame sweeps.
  Timer-based sweeps cause visible steps at 60 Hz and can't express ease curves.
- Phase chain uses a `ProgressPhase` enum (idle/stageOne/stageTwo/completing). The
  completion handler of phase N checks that `progressPhase` is still N before
  starting N+1; otherwise treat it as cancelled. This replaces needing to hold
  Animation instances for cancellation.
- Anchor the animated view's `layer.anchorPoint = (0, 0.5)` so width grows from the
  left edge when you animate `frame.size.width`.
- Monotonic invariant: clamp each phase's target to `max(currentRatio, target)` so
  re-entry or races never shrink the fill.

## Accessory app + Cmd+, global shortcut (F7)
- `NSApp.setActivationPolicy(.accessory)` apps that only set `statusItem.menu`
  cannot receive `keyEquivalent` presses when the main window is frontmost — the
  status-item menu only processes keyEquivalents while popped open.
- Fix: build a separate `NSApp.mainMenu` with an Application menu whose first
  submenu contains the `Preferences... ⌘,` item. macOS then routes the
  shortcut through the responder chain to that menu item regardless of which
  app window is key.
- Drop the duplicate `keyEquivalent: ","` on any status-item items; with the
  mainMenu owning the shortcut, status-item duplicates are dead code.

## SwiftUI @State hoisting for menu-driven tab switches (F7)
- `@State` inside a SwiftUI view can't be mutated from AppKit (AppDelegate / NSMenu
  action). Introduce a small `ObservableObject` (`@Published` tab enum), hold it
  on the `NSWindowController`, pass it as `@ObservedObject` into the SwiftUI
  root, and let the AppKit action mutate it.
- Swap `@State` → `@ObservedObject` in the view; the sidebar button taps still
  write through (`navigation.selectedSection = ...`) because `@Published`
  re-renders on write.

## Hot-reloaded config — don't cache the API key (F10)
- Services that need values that can change at runtime (API keys, provider
  config) must NOT store them as instance state. Read through a `Config` enum
  that re-parses `.env` every call.
- Cost: one ~100-byte file read per HTTPS request; negligible next to the
  network round-trip.
- Benefit: no notification plumbing, no cache-coherence bugs. Settings writes
  `~/.voice-dictation/.env`; the next request sees the new value.
- Throw `missingAPIKey` (or similar) when `Config.apiKey == nil` so the normal
  error path in the pipeline (pill failure + system notification) surfaces the
  problem; don't crash.
