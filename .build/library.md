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

## In-app toast NSPanel config (F5)
- Same floating-panel recipe as the pill works for top-right toasts:
  `nonactivatingPanel + borderless + level=.floating + hidesOnDeactivate=false +
  collectionBehavior=[.canJoinAllSpaces, .fullScreenAuxiliary] + backgroundColor=.clear +
  hasShadow=false`.
- `ignoresMouseEvents = true` for info toasts keeps them purely visual — they
  don't block clicks in the app underneath. Error toasts keep mouse events
  enabled so hover can pause the dismiss timer.
- Screen coords: `NSScreen.visibleFrame` is bottom-origin. Top-right anchoring:
  `y = visible.maxY - topInset - height - index * (height + spacing)`.
- Stack eviction: compare `active.count >= maxStack` before creating the new
  panel; dismiss oldest synchronously (no animation) so frame slots free up.
- AttributedString in SwiftUI does NOT let you set `strikethroughColor` at
  per-run level (missing from the Attribute scope) — drop it and let the
  foreground color carry through; set `foregroundColor` + `strikethroughStyle`.

## Word-level diff in ComparisonView (F8)
- Don't use Apple `NLTokenizer(.word)` for Chinese — unstable word boundaries
  (e.g. "对对对" splits to ["对","对对"]) wreck LCS matching.
- Hand-rolled Unicode scalar scan: CJK per-char + Latin/Digit run, skip
  whitespace/punct (they become `unchanged` gaps). ~80 lines no deps.
- After LCS, merge adjacent same-kind segments so multi-word deletions render
  as one visual block instead of shredded individual characters.
- Standalone swift test scripts (`Tests/test_differ.swift`) can't `import` the
  app module. Embed a copy of the algorithm in the test file and note the
  mirroring requirement in a comment.

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

## Floating panel subclass for focus discipline (toast + pill)
- ANY `NSPanel` whose content may receive mouse events must be a subclass that
  overrides `canBecomeKey` and `canBecomeMain` to return `false`. A vanilla
  `NSPanel(...)` with `.nonactivatingPanel` still promotes to key on interior
  clicks, stealing focus from the user's front-most text field.
- Mirror for `ToastPanel`: only `ignoresMouseEvents = true` would avoid the
  need, but error toasts need hover/close → must be a subclass.

## SwiftUI-in-NSHostingController retain cycle via captured closures
- Pattern: outer class holds `item` that owns `NSPanel` → `contentViewController`
  → `NSHostingController.view` → SwiftUI tree containing closures that captured
  `item` (so the closures can dismiss / update hover state). This is a strong
  cycle; `orderOut(nil)` is NOT sufficient to release — the hosting controller
  and SwiftUI host stay alive.
- Fix in dismiss's completion: set `panel.contentViewController = nil` and
  `panel.contentView = nil` before dropping the item reference. That severs
  the panel→hosting-controller edge and the whole chain collapses.
- Rule of thumb: if your dismiss path keeps the panel around, it's fine; if
  the panel should die, nil its content out first.

## Toast relayout must skip in-flight dismissals
- With a dismiss animation (0.14s), a toast about to disappear still lives in
  `active` until the completion handler runs. If a new toast arrives inside
  that window and triggers `relayout`, the fading panel's `animator().setFrame`
  fights its own dismiss animation — visually reads as "jump a row then vanish".
- Fix: iterate a `visible slot` counter in relayout that skips `dismissed == true`
  items, and compute the incoming toast's frame with the same filter
  (`active.filter { !$0.dismissed }.count - 1`).

## Differ: case-insensitive LCS + extended Latin range
- LCS comparison keys must be lowercased — LLM cleanup often re-capitalizes
  proper nouns ("claude" → "Claude"); without lowercasing those are assumed
  deleted (false positive). Display strings still come from the original-case
  token list.
- `isLatin` must cover Latin-1 Supplement + Extended-A/B (U+00C0–U+024F, minus
  multiplication/division sign 0x00D7/0x00F7). Narrower ranges shred "café",
  "résumé", "naïve" at the accented scalar, producing misaligned runs the LCS
  can't match end-to-end.

## Dual-mode HotkeyManager + hot reload (F9)
- Single `CGEvent.tapCreate` with `mask = (1<<flagsChanged)|(1<<keyDown)`
  covers BOTH "hold-to-talk" (single modifier) and "press-to-toggle" (chord).
  No need to recreate the tap when switching modes — just atomically swap the
  `currentHotkey: HotkeyType` field, the callback reads it each event.
- `reload(to:)` MUST reset `isModifierDown = false` before overwriting
  `currentHotkey`. Otherwise the old mode's "key held down" residue leaks
  into the new mode (e.g. switching from right-Option to Fn mid-hold would
  leave isModifierDown=true and the first Fn tap would emit UP instead of DOWN).
- Esc (keyCode 53) cancel path is shared across both modes, gated only by
  `isActive` (pipeline sets this true during recording). Esc outside
  recording passes through unmolested.
- Pipeline must observe `Notification.Name.hotkeyConfigChanged` and call
  `reload(to: Config.hotkey)` + proactively `handleCancel()` if recording
  is in flight at the moment of switch (the old binding's release event
  will never arrive).

## Single-modifier keycodes that lack a CGEventFlags bit
- CapsLock (57) and Fn (63) generate `flagsChanged` events but do NOT
  set any bit in the `[.maskCommand, .maskShift, .maskAlternate, .maskControl]`
  mask. `intersection(mask) == []` is true for both press AND release — can't
  disambiguate from the mask alone.
- Workaround: track `isModifierDown` internally and flip on each flagsChanged
  for that keyCode. Works because those keys emit one flagsChanged per
  physical state change. Non-Fn/CapsLock lone-modifier keys still use the
  `pressed == own-flag` check.

## Conflict detection for user-configurable hotkeys: static blocklist only
- `Carbon.RegisterEventHotKey` only sees the current process's registrations.
  It returns `noErr` for system-reserved keys (Cmd+Space/Spotlight,
  Cmd+Tab/switcher, Cmd+Shift+5/screencap) — verified false-positive on macOS
  14. There is no public API to query system-wide hotkeys or third-party
  (Alfred/Raycast/Hammerspoon) bindings.
- The only workable design: static `knownConflicts` array hardcoding the
  ~10 most common system-reserved combos, exposed via
  `HotkeyManager.conflictDescription(for:)` for SettingsView to show an
  inline warning. Follow spec "只提示不拦截" — still allow save.

## NSEvent.addLocalMonitorForEvents for hotkey recording
- Use `.local` monitor (fires only while app is key) to record a new hotkey
  from the Settings UI. Returning nil from the monitor swallows the event so
  it doesn't bleed into the form's text fields (e.g. the API-key TextField).
- `NSEvent.modifierFlags` → `CGEventFlags` needs a manual translation
  (`.command → .maskCommand`, `.option → .maskAlternate`, etc.) so the same
  `knownConflicts` list works for both the global tap path and the local
  recording path.
- Classifier rule: lone modifier keys (54/55/56/60/58/61/59/62/57/63) with
  no *other* modifier held → `.singleModifier`. Non-modifier keyDown with
  at least one modifier held → `.chord`. Reject plain letter keys with no
  modifiers (captures every keystroke in the form — terrible UX).

## HotkeyType Codable with associated values
- `enum HotkeyType: Codable` with associated values (`.singleModifier(keyCode:)`
  and `.chord(keyCode:modifiers:)`) gets automatic Codable conformance in
  Swift 5.5+ — no custom encoder/decoder needed.
- Store modifiers as `UInt64` (not `CGEventFlags`), because CGEventFlags
  isn't Codable. Convert at the edge: `CGEventFlags(rawValue: ...)`.
- UserDefaults persistence: `JSONEncoder().encode(hotkey)` → Data → setData.
  Read the other way. 4-line get/set in Config.swift.

## Chord recording state machine: commit-on-release not commit-on-press (F9)
- Naive design "commit on first flagsChanged with a modifier flag set"
  breaks chord recording: pressing Cmd alone triggers flagsChanged with
  `pressed == {maskCommand}` which immediately commits `singleModifier(Cmd)`;
  the user never gets to press Space.
- Fix: track `pendingModifierKeyCode` + `sawKeyDownDuringHold`. First lone
  modifier press sets `pendingModifierKeyCode` and waits. keyDown with
  modifiers → commit chord. All-release (`pressed.isEmpty`) with pending
  and no keyDown observed → commit single-modifier. CapsLock/Fn still
  commit on first flagsChanged (no modifier bit to disambiguate press vs
  release). Full implementation in `SettingsView.swift` HotkeyRecorderControl.

## Global CGEventTap must passthrough during hotkey recording (F9 Blocker)
- A CGEventTap at `.cgSessionEventTap` runs in HID layer BEFORE any
  per-window NSEvent monitor. Default-tap returning `nil` consumes the
  event system-wide → Settings' local NSEvent monitor never sees it.
- Add `beginCapture()` / `endCapture()` on the manager setting an
  `isCapturing` flag (guarded by `os_unfair_lock` since the callback
  thread is not main). When set, callback first thing: return
  `Unmanaged.passUnretained(event)` — pass through, no dispatch, no consume.
- Wire it via `Notification.Name.hotkeyCaptureBegin` / `.hotkeyCaptureEnd`
  so the Settings view doesn't need a direct reference to the pipeline's
  HotkeyManager instance.
- Also reset `isModifierDown` at both begin and end: a stale "held" flag
  from before capture would otherwise fire a spurious `.singleModifierUp`
  to the pipeline once the user finishes recording.

## os_unfair_lock in Swift (CGEventTap callback + main-thread writers)
- `os_unfair_lock_t` is an `UnsafeMutablePointer<os_unfair_lock>`. Allocate
  in a stored property initializer (`UnsafeMutablePointer.allocate(capacity:1)`
  then `initialize(to: os_unfair_lock())`) and free in `deinit` with
  `deinitialize(count:1)` + `deallocate()`. Do NOT use
  `withUnsafeMutablePointer(to: &storedStruct)` — Swift struct addresses
  aren't stable across accesses.
- Pattern for reading Codable enum fields across threads: wrap read/write
  of the stored `_state` in `os_unfair_lock_lock/unlock`, snapshot the
  value into a local while holding the lock, use the snapshot after release.
  Enums with 2+ word payloads (like `HotkeyType.chord(Int64, UInt64)`) can
  otherwise tear on the reader side.

## Persistent conflict state is orthogonal to "just saved" flash
- Original design collapsed conflict-indicator into `Phase.justSaved`, so
  the warning color disappeared 1.2s after save even though the hotkey
  was still conflicting. Reviewers will flag this.
- Keep `Phase` strictly about transient flashing (idle/recording/justSaved)
  and derive `hasConflict: Bool` from `conflictHint != nil && phase != .recording`.
  Then each visual token (foreground / background / border) first checks
  `hasConflict` and only falls through to phase-based colors when clean.
