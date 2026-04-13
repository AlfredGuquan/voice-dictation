# Voice Dictation - Services

## Build
- `swift build` from project root. Target: macOS 13+, Swift 5.9.
- No external dependencies (pure SPM, no third-party packages).
- Linked frameworks: AppKit, AVFoundation, CoreGraphics.

## Runtime
- Requires Accessibility permission (System Preferences > Privacy > Accessibility).
- Reads `~/.voice-dictation/.env` for `OPENAI_API_KEY`.
- Vocabulary stored at `~/.voice-dictation/vocabulary.json` (auto-created on first run).
- History stored by `HistoryStore` (file-based).

## Key Architecture
- Single executable target (`VoiceDictation`), no library targets.
- `DictationPipeline` orchestrates: hotkey -> record -> Whisper ASR -> LLM cleanup -> text injection.
- `HotkeyManager` uses CGEvent tap (requires Accessibility).
- `TextInjector` uses clipboard + Cmd+V paste (AX API for focus detection).
- `FloatingPillPanel` is a non-activating NSPanel that floats above all windows.
