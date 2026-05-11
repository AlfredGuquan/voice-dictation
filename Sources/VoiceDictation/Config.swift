import Foundation

/// Runtime configuration read from .env / UserDefaults on every access.
/// Services must NOT cache these values — Settings writes them and the next
/// request should pick them up without an app restart.
enum Config {
    /// OpenAI API key, from `~/.voice-dictation/.env`.
    static var apiKey: String? {
        let value = EnvLoader.load()["OPENAI_API_KEY"]
        guard let value = value, !value.isEmpty else { return nil }
        return value
    }

    // MARK: - Dictation hotkey

    private static let hotkeyDefaultsKey = "dictationHotkey"

    /// User-configured dictation hotkey. Reads from UserDefaults; falls back
    /// to right Option single-modifier (the historical default) if unset or
    /// unparseable.
    static var hotkey: HotkeyManager.HotkeyType {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: hotkeyDefaultsKey),
                let decoded = try? JSONDecoder().decode(HotkeyManager.HotkeyType.self, from: data)
            else {
                return .singleModifier(keyCode: 61)  // right Option
            }
            return decoded
        }
        set {
            do {
                let data = try JSONEncoder().encode(newValue)
                UserDefaults.standard.set(data, forKey: hotkeyDefaultsKey)
            } catch {
                // HotkeyType is a simple enum with Int64/UInt64 payloads;
                // encoding should never fail. Surface it loudly in DEBUG
                // so a future schema change can't silently drop the
                // user's hotkey.
                print("[Config] Failed to encode hotkey \(newValue): \(error)")
                #if DEBUG
                assertionFailure("Config.hotkey encode failed: \(error)")
                #endif
            }
        }
    }

    // MARK: - LLM cleanup mode

    /// Whether to run GPT-4o-mini cleanup on the raw transcript.
    /// - `.always`: always call the cleanup model (historical behavior).
    /// - `.auto`:   skip cleanup when the raw transcript has no fillers, no
    ///              obvious repeats, and the vocabulary store has no
    ///              replacements to apply. Falls back to calling otherwise.
    /// - `.never`:  never call cleanup; paste the raw Whisper output.
    ///
    /// Resolution order: `VD_CLEANUP_MODE` env var → UserDefaults → `.auto`.
    /// Env var is intended for bench/A-B; UserDefaults is for future Settings UI.
    enum CleanupMode: String {
        case always
        case auto
        case never
    }

    static var cleanupMode: CleanupMode {
        if let env = ProcessInfo.processInfo.environment["VD_CLEANUP_MODE"],
           let mode = CleanupMode(rawValue: env) {
            return mode
        }
        if let stored = UserDefaults.standard.string(forKey: "cleanupMode"),
           let mode = CleanupMode(rawValue: stored) {
            return mode
        }
        return .auto
    }

    // MARK: - Open-window hotkey

    private static let openWindowHotkeyDefaultsKey = "openWindowHotkey"

    /// Optional global hotkey to bring the main window forward. Nil = unset
    /// (no global shortcut registered). Distinct from the dictation hotkey;
    /// must be a chord (single-modifier rejected at the SettingsView layer).
    static var openWindowHotkey: HotkeyManager.HotkeyType? {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: openWindowHotkeyDefaultsKey),
                let decoded = try? JSONDecoder().decode(HotkeyManager.HotkeyType.self, from: data)
            else {
                return nil
            }
            return decoded
        }
        set {
            if let newValue = newValue {
                do {
                    let data = try JSONEncoder().encode(newValue)
                    UserDefaults.standard.set(data, forKey: openWindowHotkeyDefaultsKey)
                } catch {
                    print("[Config] Failed to encode openWindowHotkey \(newValue): \(error)")
                    #if DEBUG
                    assertionFailure("Config.openWindowHotkey encode failed: \(error)")
                    #endif
                }
            } else {
                UserDefaults.standard.removeObject(forKey: openWindowHotkeyDefaultsKey)
            }
        }
    }
}

/// Posted by SettingsView after writing a new hotkey into Config.
/// DictationPipeline listens and calls HotkeyManager.reload(to:).
extension Notification.Name {
    static let hotkeyConfigChanged = Notification.Name("voice-dictation.hotkeyConfigChanged")
    /// Posted by the Settings hotkey recorder when it enters recording mode.
    /// DictationPipeline forwards to HotkeyManager.beginCapture() so the
    /// global CGEventTap stops swallowing events during recording.
    static let hotkeyCaptureBegin = Notification.Name("voice-dictation.hotkeyCaptureBegin")
    /// Posted when the Settings hotkey recorder exits recording mode.
    static let hotkeyCaptureEnd = Notification.Name("voice-dictation.hotkeyCaptureEnd")
    /// Posted by SettingsView after writing Config.openWindowHotkey.
    /// AppDelegate listens and re-registers the Carbon event hotkey.
    static let openWindowHotkeyChanged = Notification.Name("voice-dictation.openWindowHotkeyChanged")
}
