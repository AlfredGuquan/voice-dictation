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
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: hotkeyDefaultsKey)
            }
        }
    }
}

/// Posted by SettingsView after writing a new hotkey into Config.
/// DictationPipeline listens and calls HotkeyManager.reload(to:).
extension Notification.Name {
    static let hotkeyConfigChanged = Notification.Name("voice-dictation.hotkeyConfigChanged")
}
