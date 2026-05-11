import Foundation

/// Calls GPT-4o-mini to clean up raw transcription.
/// Removes filler words, repeated phrases; preserves original meaning.
final class LLMCleanupService {
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    enum CleanupError: Error, LocalizedError {
        case networkError(String)
        case apiError(String)
        case invalidResponse
        case missingAPIKey

        var errorDescription: String? {
            switch self {
            case .networkError(let msg): return "Network error: \(msg)"
            case .apiError(let msg): return "API error: \(msg)"
            case .invalidResponse: return "Invalid response from cleanup API"
            case .missingAPIKey: return "OPENAI_API_KEY not set"
            }
        }
    }

    private let baseSystemPrompt = """
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

    /// Build full system prompt, optionally injecting vocabulary instructions.
    func buildSystemPrompt(vocabulary: VocabularyStore.Vocabulary? = nil) -> String {
        var prompt = baseSystemPrompt

        guard let vocab = vocabulary else { return prompt }

        if !vocab.recognitionWords.isEmpty {
            let words = vocab.recognitionWords.joined(separator: "、")
            prompt += "\n\n以下专有名词必须保持原样：\(words)"
        }

        if !vocab.replacements.isEmpty {
            let lines = vocab.replacements.map { "\($0.key) → \($0.value)" }
            prompt += "\n\n以下词语需要替换：\(lines.joined(separator: "、"))"
        }

        return prompt
    }

    /// Heuristic: when the raw transcript has no filler words, no obvious
    /// 3+ character repeats, and there are no vocabulary substitutions to
    /// apply, GPT cleanup is essentially a no-op — the user-visible diff is
    /// zero but we pay a ~4s LLM round trip. Returns `true` when we can
    /// safely skip cleanup and paste the raw text directly.
    static func canSkipCleanup(rawText: String, vocabulary: VocabularyStore.Vocabulary?) -> Bool {
        // Replacements only require LLM when the transcript actually contains
        // a key the user wants substituted. An untriggered entry shouldn't
        // force a 4s round trip.
        if let vocab = vocabulary {
            for key in vocab.replacements.keys where rawText.contains(key) {
                return false
            }
        }
        let fillers = ["嗯", "啊", "哦", "呃", "就是说", "那个", "然后", "就是", "对对对", "是的是的"]
        for filler in fillers {
            if rawText.contains(filler) { return false }
        }
        // 3+ identical CJK chars in a row indicates a stutter/repeat that
        // cleanup would collapse.
        let chars = Array(rawText)
        var run = 1
        for i in 1..<chars.count {
            if chars[i] == chars[i-1] && chars[i].isCJKIdeograph {
                run += 1
                if run >= 3 { return false }
            } else {
                run = 1
            }
        }
        return true
    }

    /// Clean up raw transcription text, optionally applying personal vocabulary.
    func cleanup(rawText: String, vocabulary: VocabularyStore.Vocabulary? = nil) async throws -> String {
        if rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ""
        }

        guard let apiKey = Config.apiKey else {
            throw CleanupError.missingAPIKey
        }

        let prompt = buildSystemPrompt(vocabulary: vocabulary)

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "temperature": 0.3,
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": rawText],
            ],
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 12
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await NetworkClient.session.data(for: request)
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

private extension Character {
    var isCJKIdeograph: Bool {
        guard let scalar = unicodeScalars.first?.value else { return false }
        return (0x4E00...0x9FFF).contains(scalar)
            || (0x3400...0x4DBF).contains(scalar)
            || (0x20000...0x2A6DF).contains(scalar)
    }
}
