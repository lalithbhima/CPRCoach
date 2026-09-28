import Foundation

/// Emergency Voice AI — full guided dispatcher flow, then OpenRouter for active CPR conversation.
@MainActor
final class EmergencyVoiceAssistant {
    enum Reply {
        case scripted(EmergencyGuidedFlowEngine.Turn)
        case openRouter(userMessage: String, metrics: CPRMetrics?, joints: BodyJoints?)
    }

    private let guidedFlow = EmergencyGuidedFlowEngine()
    private let rag = RAGRetriever.shared
    private let llm = OpenRouterLLMEngine.shared

    private var activeCoachingSystemPrompt: String {
        let lang = LanguageManager.shared
        return [
            lang.text("emergency_openrouter_system_prompt"),
            lang.textFormat("llm_reply_language", lang.current.name, lang.current.name)
        ].joined(separator: "\n\n")
    }

    var isAvailable: Bool { true }
    var availabilityMessage: String { LanguageManager.shared.text("voice_ai_ready") }
    var currentStep: EmergencyGuidedFlowEngine.Step { guidedFlow.step }

    func resetSession() {
        guidedFlow.reset()
        BuiltInCPRVoiceEngine.shared.resetSession()
        llm.resetEmergencyVoiceSession()
    }

    func prepareSession() {
        resetSession()
        llm.prepareEmergencyVoiceSession(systemInstructions: activeCoachingSystemPrompt)
    }

    func openingPrompt() -> EmergencyGuidedFlowEngine.Turn {
        guidedFlow.openingTurn()
    }

    func respond(
        to userMessage: String,
        metrics: CPRMetrics?,
        joints: BodyJoints?
    ) -> Reply {
        let turn = guidedFlow.advance(userInput: userMessage, metrics: metrics, joints: joints)
        if turn.useOpenRouter {
            return .openRouter(userMessage: userMessage, metrics: metrics, joints: joints)
        }
        return .scripted(turn)
    }

    func fetchOpenRouterCoaching(
        userMessage: String,
        metrics: CPRMetrics?,
        joints: BodyJoints?
    ) async -> EmergencyGuidedFlowEngine.Turn {
        let grounding = buildGrounding(for: userMessage, metrics: metrics, joints: joints)

        if llm.isConfigured {
            do {
                let raw = try await llm.respondEmergencyVoice(userMessage: userMessage, groundingContext: grounding)
                let speech = ChatResponseFormatter.plainText(from: raw)
                if !speech.isEmpty {
                    return activeTurn(speech: speech)
                }
            } catch {
                // Fall through to built-in coach.
            }
        }

        let fallback = (try? BuiltInCPRVoiceEngine.shared.respond(to: userMessage, metrics: metrics, joints: joints))
            ?? LanguageManager.shared.text("guided_keep_going")
        return activeTurn(speech: fallback)
    }

    func summarizeConversation(_ log: [ChatMessage]) -> String {
        if log.isEmpty {
            return LanguageManager.shared.text("emergency_summary_empty")
        }
        return guidedFlow.summarizeSession()
    }

    // MARK: - Private

    private func activeTurn(speech: String) -> EmergencyGuidedFlowEngine.Turn {
        EmergencyGuidedFlowEngine.Turn(
            speech: speech,
            step: .activeCoaching,
            flowState: .activeCoaching,
            sessionEnded: false
        )
    }

    private func buildGrounding(
        for question: String,
        metrics: CPRMetrics?,
        joints: BodyJoints?
    ) -> String {
        let chunks = rag.retrieve(for: question, limit: 4)
        var parts = chunks.map { "[\($0.topic)]: \($0.content)" }

        if let joints, let metrics {
            let analysis = JointAnalysisEngine.analyze(joints: joints, metrics: metrics)
            parts.append("Joint analysis: \(analysis.nodeSummary). Issue: \(analysis.alignmentIssue ?? "none").")
        }
        if let metrics, metrics.compressionsPerMinute > 1 {
            parts.append(
                "Live metrics: \(Int(metrics.compressionsPerMinute)) CPM, depth \(String(format: "%.1f", metrics.estimatedDepthCm)) cm, placement \(metrics.handPlacement.rawValue), elbow \(Int(metrics.elbowAngle))°, recoil \(metrics.recoilQuality.rawValue)."
            )
        }

        return parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
