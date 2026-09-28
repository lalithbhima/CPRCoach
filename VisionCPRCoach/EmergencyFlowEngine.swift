import Foundation
import Combine

/// Guided emergency voice flow — speaks each CPR step, listens, then advances like a phone dispatcher.
@MainActor
final class EmergencyFlowEngine: ObservableObject {
    @Published var flowState: CPRFlowState = .ready
    @Published var guidanceMessage: String = ""
    @Published var conversationLog: [ChatMessage] = []
    @Published var sessionSummary: String?
    @Published var isVoiceAIActive = false
    @Published var isProcessing = false
    @Published var llmStatus: String = ""
    @Published var currentGuidedStep: String = ""

    private let voiceCoach: VoiceCoach
    private let voiceAssistant = EmergencyVoiceAssistant()
    private weak var speechManager: SpeechRecognitionManager?
    private var liveContext: (() -> (CPRMetrics?, BodyJoints?))?
    private var sessionEnded = false
    private var hasStartedListeningThisSession = false

    init(voiceCoach: VoiceCoach) {
        self.voiceCoach = voiceCoach
        llmStatus = voiceAssistant.availabilityMessage
        guidanceMessage = t("emergency_voice_idle")
    }

    var voiceAssistantAvailable: Bool { voiceAssistant.isAvailable }

    func setLiveContext(_ provider: @escaping () -> (CPRMetrics?, BodyJoints?)) {
        liveContext = provider
    }

    func refreshLLMStatus() {
        llmStatus = voiceAssistant.availabilityMessage
    }

    func toggleVoiceAI(speech: SpeechRecognitionManager) {
        if isVoiceAIActive {
            stopVoiceAI()
        } else {
            startVoiceAI(speech: speech)
        }
    }

    func startVoiceAI(speech: SpeechRecognitionManager) {
        refreshLLMStatus()

        speechManager = speech
        isVoiceAIActive = true
        isProcessing = false
        sessionEnded = false
        sessionSummary = nil
        conversationLog.removeAll()
        hasStartedListeningThisSession = false

        speech.requestAuthorization()
        speech.prepareListeningSession()
        voiceAssistant.prepareSession()

        Task {
            _ = await speech.ensurePermissions()
            guard self.isVoiceAIActive else { return }
            let opening = self.voiceAssistant.openingPrompt()
            self.applyTurn(opening, isOpening: true)
        }
    }

    func stopVoiceAI() {
        isVoiceAIActive = false
        isProcessing = false
        speechManager?.stopListening()
        speechManager = nil
        voiceCoach.onFinishedSpeaking = nil
        voiceCoach.stop()
        voiceAssistant.resetSession()
        guidanceMessage = t("emergency_voice_ended")
        sessionSummary = voiceAssistant.summarizeConversation(conversationLog)
        currentGuidedStep = ""
    }

    func reset() {
        if isVoiceAIActive {
            speechManager?.stopListening()
        }
        isVoiceAIActive = false
        isProcessing = false
        sessionEnded = false
        speechManager = nil
        voiceCoach.onFinishedSpeaking = nil
        voiceCoach.stop()
        voiceAssistant.resetSession()
        flowState = .ready
        conversationLog.removeAll()
        sessionSummary = nil
        currentGuidedStep = ""
        refreshLLMStatus()
        guidanceMessage = t("emergency_voice_idle")
    }

    func processVoiceInput(_ text: String) {
        guard isVoiceAIActive, !isProcessing, !sessionEnded else { return }

        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        appendUserMessage(raw)
        isProcessing = true
        guidanceMessage = t("emergency_voice_processing")
        speechManager?.pauseForSpeech()

        let (metrics, joints) = liveContext?() ?? (nil, nil)
        let reply = voiceAssistant.respond(to: raw, metrics: metrics, joints: joints)

        switch reply {
        case .scripted(let turn):
            isProcessing = false
            applyTurn(turn, isOpening: false)
        case .openRouter(let userMessage, let metrics, let joints):
            Task { await self.completeOpenRouterTurn(userMessage: userMessage, metrics: metrics, joints: joints) }
        }
    }

    private func completeOpenRouterTurn(
        userMessage: String,
        metrics: CPRMetrics?,
        joints: BodyJoints?
    ) async {
        defer { isProcessing = false }

        guard isVoiceAIActive, !sessionEnded else { return }

        let turn = await voiceAssistant.fetchOpenRouterCoaching(
            userMessage: userMessage,
            metrics: metrics,
            joints: joints
        )

        guard isVoiceAIActive, !sessionEnded else { return }
        applyTurn(turn, isOpening: false)
    }

    // MARK: - Private

    private func applyTurn(_ turn: EmergencyGuidedFlowEngine.Turn, isOpening: Bool) {
        flowState = turn.flowState
        currentGuidedStep = LanguageManager.shared.guidedStep(turn.step)
        sessionEnded = turn.sessionEnded

        if !isOpening {
            appendCoachMessage(turn.speech)
        } else {
            appendCoachMessage(turn.speech)
        }

        guidanceMessage = t("emergency_voice_speaking")
        speechManager?.prepareListeningSession()

        voiceCoach.onFinishedSpeaking = { [weak self] in
            self?.beginListeningAfterSpeech()
        }

        let spoken = turn.speech.trimmingCharacters(in: .whitespacesAndNewlines)
        if spoken.isEmpty {
            beginListeningAfterSpeech()
        } else {
            voiceCoach.speak(spoken, priority: .emergency)
        }
    }

    private func beginListeningAfterSpeech() {
        guard isVoiceAIActive, !isProcessing else { return }

        if sessionEnded {
            guidanceMessage = t("emergency_voice_ended")
            return
        }

        guidanceMessage = t("emergency_voice_listening")
        let reuseSession = hasStartedListeningThisSession
        hasStartedListeningThisSession = true
        let pauseSeconds = listeningPauseSeconds()
        speechManager?.startListening(pauseToEndSeconds: pauseSeconds, reuseSession: reuseSession)
    }

    private func t(_ key: String) -> String {
        LanguageManager.shared.text(key)
    }

    /// Slightly longer pause for languages that need more time per utterance.
    private func listeningPauseSeconds() -> TimeInterval {
        switch LanguageManager.shared.current.code {
        case "te", "ta", "hi", "bn", "mr", "ur", "pa", "ar", "th", "fa", "he", "ja", "ko", "zh-Hans", "zh-Hant":
            return 4.0
        default:
            return 3.0
        }
    }

    private func appendCoachMessage(_ text: String) {
        conversationLog.append(ChatMessage(role: .coach, text: text, timestamp: Date()))
    }

    private func appendUserMessage(_ text: String) {
        conversationLog.append(ChatMessage(role: .user, text: text, timestamp: Date()))
    }
}
