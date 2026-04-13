import Foundation

/// Loads key-value pairs from a .env file into a dictionary.
enum EnvLoader {
    /// Search order: project .env, then ~/.voice-dictation/.env
    static func load() -> [String: String] {
        let candidates = [
            // 1. Project-local .env (development)
            Bundle.main.bundlePath + "/../.env",
            // 2. Resolved project path (when running via `swift run`)
            resolveProjectEnv(),
            // 3. User home config
            NSHomeDirectory() + "/.voice-dictation/.env",
        ].compactMap { $0 }

        for path in candidates {
            if let dict = parse(path: path), !dict.isEmpty {
                return dict
            }
        }
        return [:]
    }

    /// When running from SPM build directory, the project root is several levels up.
    private static func resolveProjectEnv() -> String? {
        // During development, __FILE__ trick won't work in SPM executable.
        // Use a well-known env var or walk up from the executable path.
        let execURL = URL(fileURLWithPath: CommandLine.arguments[0])
        // .build/debug/VoiceDictation -> walk up 3 levels to project root
        let projectRoot = execURL
            .deletingLastPathComponent()  // debug/
            .deletingLastPathComponent()  // .build/
            .deletingLastPathComponent()  // project root
        let envPath = projectRoot.appendingPathComponent(".env").path
        if FileManager.default.fileExists(atPath: envPath) {
            return envPath
        }
        return nil
    }

    private static func parse(path: String) -> [String: String]? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        var result: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            // Strip surrounding quotes
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }
}
