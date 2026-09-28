import Foundation

/// ChatCPR — single live API: OpenRouter free (`openrouter/free`), works globally.
@MainActor
final class OpenRouterLLMEngine {
    static let shared = OpenRouterLLMEngine()

    /// OpenRouter's free auto-routed model — no Llama or other paid IDs.
    static let freeModel = "openrouter/free"

    @MainActor
    enum EngineError: LocalizedError {
        case missingAPIKey
        case emptyResponse
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return LanguageManager.shared.text("chatcpr_no_api_key")
            case .emptyResponse:
                return LanguageManager.shared.text("chatcpr_empty_response")
            case .requestFailed(let detail):
                return detail
            }
        }
    }

    private var messages: [[String: String]] = []
    private var emergencyVoiceMessages: [[String: String]] = []

    var isConfigured: Bool {
        SecretsLoader.isConfigured
    }

    var statusMessage: String {
        isConfigured
            ? LanguageManager.shared.text("chatcpr_ready")
            : LanguageManager.shared.text("chatcpr_no_api_key")
    }

    private var resolvedAPIKey: String {
        SecretsLoader.openRouterAPIKey
    }

    func resetSession() {
        messages.removeAll()
    }

    func prepareSession(systemInstructions: String) {
        resetSession()
        messages.append(["role": "system", "content": systemInstructions])
    }

    func resetEmergencyVoiceSession() {
        emergencyVoiceMessages.removeAll()
    }

    func prepareEmergencyVoiceSession(systemInstructions: String) {
        resetEmergencyVoiceSession()
        emergencyVoiceMessages.append(["role": "system", "content": systemInstructions])
    }

    /// Active CPR coaching only — separate history from ChatCPR.
    func respondEmergencyVoice(userMessage: String, groundingContext: String) async throws -> String {
        guard isConfigured else { throw EngineError.missingAPIKey }

        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EngineError.emptyResponse }

        var userContent = trimmed
        if !groundingContext.isEmpty {
            userContent = """
            CPR reference (ground answers in these facts):
            \(groundingContext)

            User: \(trimmed)
            """
        }

        emergencyVoiceMessages.append(["role": "user", "content": userContent])
        let reply = try await callChatAPI(messages: emergencyVoiceMessages, maxTokens: 180)
        emergencyVoiceMessages.append(["role": "assistant", "content": reply])
        return reply
    }

    /// One-shot completion (Progress analytics, no chat history).
    func completeOnce(system: String, user: String, maxTokens: Int = 400) async throws -> String {
        guard isConfigured else { throw EngineError.missingAPIKey }
        let messages = [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ]
        return try await callChatAPI(messages: messages, maxTokens: maxTokens)
    }

    func respond(userMessage: String, groundingContext: String) async throws -> String {
        guard isConfigured else { throw EngineError.missingAPIKey }

        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EngineError.emptyResponse }

        var userContent = trimmed
        if !groundingContext.isEmpty {
            userContent = """
            CPR reference (ground answers in these facts):
            \(groundingContext)

            User: \(trimmed)
            """
        }

        messages.append(["role": "user", "content": userContent])
        let reply = try await callChatAPI(messages: messages, maxTokens: 600)
        messages.append(["role": "assistant", "content": reply])
        return reply
    }

    private func callChatAPI(messages: [[String: String]], maxTokens: Int) async throws -> String {
        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else {
            throw EngineError.requestFailed("Invalid OpenRouter URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(resolvedAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://vision-cpr-coach.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Vision CPR Coach ChatCPR", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 90

        let body: [String: Any] = [
            "model": Self.freeModel,
            "messages": messages,
            "max_tokens": maxTokens,
            "temperature": 0.35
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw EngineError.requestFailed("No response from OpenRouter.")
        }

        if http.statusCode != 200 {
            let detail = parseErrorBody(data) ?? "HTTP \(http.statusCode)"
            throw EngineError.requestFailed(detail)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let content = (message?["content"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let content, !content.isEmpty else {
            throw EngineError.emptyResponse
        }
        return content
    }

    private func parseErrorBody(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return String(data: data, encoding: .utf8)
        }
        return message
    }
}
