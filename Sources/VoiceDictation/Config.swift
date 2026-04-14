import Foundation

/// Runtime configuration read from .env on every access.
/// Services must NOT cache the key—Settings writes the file and the next
/// request should pick it up without an app restart.
enum Config {
    static var apiKey: String? {
        let value = EnvLoader.load()["OPENAI_API_KEY"]
        guard let value = value, !value.isEmpty else { return nil }
        return value
    }
}
