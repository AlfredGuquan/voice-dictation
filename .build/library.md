# Code Library Knowledge

## Project Structure
- Swift Package Manager executable (`swift build` to compile)
- Single target: `VoiceDictation` in `Sources/VoiceDictation/`
- macOS 13+ deployment target
- No Xcode project — pure SPM

## Key Patterns

### Global Hotkey via CGEvent Tap
- `CGEvent.tapCreate` with `.cgSessionEventTap` — requires Accessibility permission
- Filter `flagsChanged` for keyCode 61 (right Option) and `keyDown` for keyCode 53 (Esc)
- Swallow events by returning nil from callback
- Must re-enable tap on `.tapDisabledByTimeout` events (system disables taps under load)
- Event tap callback must dispatch to main thread for UI work

### Audio Recording
- `AVAudioEngine.inputNode` captures from default mic
- Install tap on bus 0, write buffers to `AVAudioFile`
- WAV format: Int16 PCM at system sample rate (usually 48kHz)
- Must call `removeTap(onBus:)` before `engine.stop()`, and nil the file to flush

### Text Injection (Clipboard Paste Method)
- Save all clipboard types (not just string) for faithful restoration
- CGEvent key simulation: virtualKey 0x09 = 'V', `.maskCommand` flag for Cmd
- Post to `.cghidEventTap` for system-wide delivery
- 200-250ms delay before restoring clipboard (paste needs time to process)
- **Do NOT use per-character CGEvent** — breaks CJK input (tracer-verified)

### Floating Panel (Non-Activating)
- Custom `NSPanel` subclass: `canBecomeKey = false`, `canBecomeMain = false`
- Style: `[.nonactivatingPanel, .borderless]`
- `hidesOnDeactivate = false` — critical for accessory apps (no active state)
- `collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary]`
- `NSApp.setActivationPolicy(.accessory)` — no Dock icon, no app switcher

### Warm Glass Visual Theme
- Background: `rgba(255, 253, 250, 0.82)` over `NSVisualEffectView(.hudWindow)`
- Accent (terracotta): `#D97757`, hover: `#C4653A`
- Confirm (green): `#5D8C5A`, bg: `rgba(93,140,90,0.10)`
- Cancel (red-ish): `#C4653A`, bg: `rgba(196,101,58,0.08)`
- Pill shape: 280x48px, cornerRadius = height/2
- Shadow: `0 4px 24px rgba(0,0,0,0.06)`

### .env Loading Strategy
- SPM executable runs from `.build/debug/VoiceDictation`
- Walk up 3 levels from executable path to find project root `.env`
- Fallback: `~/.voice-dictation/.env`

### Personal Vocabulary (VocabularyStore)
- File: `~/.voice-dictation/vocabulary.json` — JSON with `recognitionWords` array and `replacements` dict
- `VocabularyStore.load()` creates dir + default file if missing, then starts DispatchSource file watcher
- File watcher handles atomic writes (delete+rename) by restarting the watcher after 200ms delay
- Vocabulary injected into LLM cleanup via `LLMCleanupService.buildSystemPrompt(vocabulary:)`
- `cleanup(rawText:vocabulary:)` has default nil parameter — backward compatible, existing callers unaffected
- Recognition words appended as "以下专有名词必须保持原样：{words}" to system prompt
- Replacements appended as "以下词语需要替换：{trigger} → {replacement}" to system prompt
- VocabularyStore also exposes `recognitionWordsPrompt()` / `replacementsPrompt()` for future UI use

### Main Window (SwiftUI in NSWindow)
- `MainWindowController` creates an `NSWindow` with `NSHostingView` wrapping SwiftUI `MainContentView`
- `window.isReleasedWhenClosed = false` — keeps the window object alive so re-opening works without recreating
- App starts as `.accessory` (no Dock icon) but calls `NSApp.activate(ignoringOtherApps: true)` when opening main window — this brings the window to front
- Sidebar navigation uses enum `SidebarSection` with `.history`, `.vocabulary`, `.settings`
- History comparison view is reached by setting `selectedRecordID` (not a separate NavigationLink), back button clears it

### HistoryStore
- `HistoryStore` is `ObservableObject` with `@Published records` for SwiftUI reactivity
- Uses `Combine` import (not SwiftUI) to get `ObservableObject` and `@Published` without pulling in SwiftUI framework in the data layer
- Records added to pipeline in `processAudio` (success path) and `handleError` (failure path)
- `DictationPipeline.historyStore` and `.vocabularyStore` are `let` (internal access) so `AppDelegate` can pass them to `MainWindowController`
- `recordingStartTime` tracked on pipeline to compute duration

### SwiftUI View Patterns
- `VocabularyView` reads from `VocabularyStore.current` on appear and maintains local `@State` copy
- After each edit operation, calls `vocabularyStore.save()` which writes to disk; file watcher picks up changes for the pipeline
- `Theme.swift` centralizes all design tokens (colors) as `Color` static properties
- `Color(hex:)` extension initializer for hex color values

## Gotchas
- SPM's `.build/` directory conflicts with knowledge files at `.build/*.md` — use gitignore negation pattern `!.build/*.md`
- `NSPanel.hidesOnDeactivate` must be explicitly set to `false` — default hides panel when app loses activation (which is always for `.accessory` apps)
- `CGEvent.tapCreate` returns nil without Accessibility permission — check at startup
- AVAudioEngine input format varies by hardware — always use `inputNode.outputFormat(forBus:)` as source of truth
- SPM executable targets cannot be `@testable import`ed — use standalone Swift scripts for unit-style testing
- DispatchSource file watcher: atomic writes (via `.atomic` option) trigger delete+rename events, not write — must handle both and restart the watcher on the new inode
- `remove(atOffsets: IndexSet)` on arrays is a SwiftUI extension — using it in non-SwiftUI files forces a SwiftUI link dependency. Use manual `removeAll(where:)` instead for data-layer code
- SwiftUI views imported in SPM executable compile fine — no special linker settings needed beyond the existing AppKit/AVFoundation/CoreGraphics. SwiftUI is auto-linked when imported
- `NSApp.activate(ignoringOtherApps: true)` is needed to bring `.accessory` app windows to front — without it, the window appears behind other apps
