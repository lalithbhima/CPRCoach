import Foundation

/// ChatCPR — live OpenRouter LLM with on-device CPR knowledge context. Typed chat only (no voice).
@MainActor
final class AICoachService: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isProcessing = false

    private let rag = RAGRetriever.shared
    private let llm = OpenRouterLLMEngine.shared

    private var systemPrompt: String {
        let lang = LanguageManager.shared
        return [
            lang.text("chatcpr_system_prompt"),
            lang.textFormat("llm_reply_language", lang.current.name, lang.current.name)
        ].joined(separator: "\n\n")
    }

    init() {
        llm.prepareSession(systemInstructions: systemPrompt)
    }

    var isLiveLLMReady: Bool { llm.isConfigured }

    func reset() {
        messages.removeAll()
        llm.prepareSession(systemInstructions: systemPrompt)
        appendSystemWelcome()
    }

    func refreshSystemPrompt() {
        llm.prepareSession(systemInstructions: systemPrompt)
    }

    func appendSystemWelcome() {
        messages.append(ChatMessage(
            role: .coach,
            text: LanguageManager.shared.text("chatcpr_welcome"),
            timestamp: Date()
        ))
    }

    func ask(
        _ question: String,
        liveMetrics: CPRMetrics? = nil,
        joints: BodyJoints? = nil
    ) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(ChatMessage(role: .user, text: trimmed, timestamp: Date()))
        isProcessing = true

        let response = await generateResponse(
            question: trimmed,
            metrics: liveMetrics,
            joints: joints
        )

        let cleaned = ChatResponseFormatter.plainText(from: response)
        messages.append(ChatMessage(role: .coach, text: cleaned, timestamp: Date()))
        isProcessing = false
    }

    private func generateResponse(
        question: String,
        metrics: CPRMetrics?,
        joints: BodyJoints?
    ) async -> String {
        let chunks = rag.retrieve(for: question, limit: 5)
        let contextText = chunks.map { "[\($0.topic)]: \($0.content)" }.joined(separator: "\n")

        var extras: [String] = []
        if let joints, let metrics {
            let analysis = JointAnalysisEngine.analyze(joints: joints, metrics: metrics)
            extras.append("Joint analysis: \(analysis.nodeSummary). Issue: \(analysis.alignmentIssue ?? "none").")
        }
        if let metrics, metrics.compressionsPerMinute > 1 {
            extras.append(metricsDescription(metrics))
        }

        let grounding = ([contextText] + extras).filter { !$0.isEmpty }.joined(separator: "\n")

        do {
            return try await llm.respond(userMessage: question, groundingContext: grounding)
        } catch {
            if let localized = error as? LocalizedError, let msg = localized.errorDescription {
                return msg
            }
            return error.localizedDescription
        }
    }

    private func metricsDescription(_ metrics: CPRMetrics) -> String {
        "Live metrics: \(Int(metrics.compressionsPerMinute)) CPM, depth \(String(format: "%.1f", metrics.estimatedDepthCm)) cm, placement \(metrics.handPlacement.rawValue), elbow \(Int(metrics.elbowAngle))°, recoil \(metrics.recoilQuality.rawValue)."
    }
}
