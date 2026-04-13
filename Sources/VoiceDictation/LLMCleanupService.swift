import Foundation

/// Calls GPT-4o-mini to clean up raw transcription.
/// Removes filler words, repeated phrases; preserves original meaning.
final class LLMCleanupService {
    private let apiKey: String
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    enum CleanupError: Error, LocalizedError {
        case networkError(String)
        case apiError(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .networkError(let msg): return "Network error: \(msg)"
            case .apiError(let msg): return "API error: \(msg)"
            case .invalidResponse: return "Invalid response from cleanup API"
            }
        }
    }

    private let systemPrompt = """
        你是语音转录的文字清洗助手。你的任务是清理语音识别的原始文本，使其更加可读。

        规则：
        1. 删除口语填充词：嗯、啊、哦、呃、就是说、那个、然后、就是、对对对、是的是的
        2. 删除重复的词或短语（如"我我我觉得" → "我觉得"）
        3. 保留原意，不要重写或重组句子结构
        4. 保留原始的标点符号风格
        5. 保留中英文混合的原始用词
        6. 如果整段文字清洗后为空，返回空字符串
        7. 只返回清洗后的文字，不要添加任何解释

        示例：
        输入：嗯，我觉得这个这个 feature 啊，就是说需要一个一个 API 来处理
        输出：我觉得这个 feature 需要一个 API 来处理
        """

    /// Clean up raw transcription text.
    func cleanup(rawText: String) async throws -> String {
        if rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ""
        }

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "temperature": 0.3,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": rawText],
            ],
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CleanupError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CleanupError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw CleanupError.apiError("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw CleanupError.invalidResponse
        }

        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[LLMCleanup] Cleaned: \(cleaned)")
        return cleaned
    }
}
