import Foundation

/// Shared URLSession for OpenAI API calls + connection prewarm.
/// One process-wide session lets consecutive Whisper / Chat requests reuse
/// the TLS connection (saves ~100-300ms per cold call vs `.shared`'s default
/// pool, which can drop connections between unrelated callers).
enum NetworkClient {

    /// Configured URLSession used by WhisperService and LLMCleanupService.
    /// HTTP/2 + keep-alive are on by default in URLSessionConfiguration.
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        // Whisper + cleanup may overlap during retry / future parallelization;
        // 6 matches OpenAI's typical per-host concurrency limit.
        config.httpMaximumConnectionsPerHost = 6
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private static let openaiBase = URL(string: "https://api.openai.com")!

    /// Track in-flight prewarms so back-to-back hotkey presses don't pile up
    /// duplicate connections. Cleared automatically when the request finishes.
    private static var prewarmInFlight = false
    private static let prewarmLock = NSLock()

    /// Fire-and-forget HEAD to api.openai.com to establish TCP + TLS + HTTP/2
    /// before the first real Whisper request needs it. Called at app start and
    /// on hotkey-down so by the time the user releases the key (~1-3s later)
    /// the connection is warm.
    static func prewarm() {
        // `VD_NO_PREWARM=1` disables the prewarm call entirely — used by the
        // bench harness for A/B testing the cold-start TLS savings.
        if ProcessInfo.processInfo.environment["VD_NO_PREWARM"] == "1" { return }
        guard let apiKey = Config.apiKey else { return }

        prewarmLock.lock()
        if prewarmInFlight {
            prewarmLock.unlock()
            return
        }
        prewarmInFlight = true
        prewarmLock.unlock()

        var request = URLRequest(url: openaiBase.appendingPathComponent("/v1/models"))
        request.httpMethod = "HEAD"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5

        let task = session.dataTask(with: request) { _, _, _ in
            prewarmLock.lock()
            prewarmInFlight = false
            prewarmLock.unlock()
        }
        task.resume()
    }
}
