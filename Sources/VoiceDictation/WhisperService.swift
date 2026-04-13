import Foundation

/// Calls OpenAI Whisper API for speech-to-text transcription.
final class WhisperService {
    private let apiKey: String
    private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    struct TranscriptionResult {
        let text: String
    }

    enum WhisperError: Error, LocalizedError {
        case networkError(String)
        case apiError(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .networkError(let msg): return "Network error: \(msg)"
            case .apiError(let msg): return "API error: \(msg)"
            case .invalidResponse: return "Invalid response from Whisper API"
            }
        }
    }

    /// Transcribe audio file using Whisper API.
    func transcribe(fileURL: URL) async throws -> TranscriptionResult {
        let boundary = UUID().uuidString

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let audioData = try Data(contentsOf: fileURL)

        var body = Data()
        // model field
        body.appendMultipart(boundary: boundary, name: "model", value: "whisper-1")
        // language field
        body.appendMultipart(boundary: boundary, name: "language", value: "zh")
        // response_format field
        body.appendMultipart(boundary: boundary, name: "response_format", value: "json")
        // file field
        body.appendMultipartFile(
            boundary: boundary,
            name: "file",
            filename: fileURL.lastPathComponent,
            mimeType: "audio/wav",
            data: audioData
        )
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw WhisperError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WhisperError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw WhisperError.apiError("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String
        else {
            throw WhisperError.invalidResponse
        }

        print("[WhisperService] Transcription: \(text)")
        return TranscriptionResult(text: text)
    }
}

// MARK: - Data multipart helpers

private extension Data {
    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipartFile(
        boundary: String, name: String, filename: String, mimeType: String, data: Data
    ) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
                .data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
