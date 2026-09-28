import Foundation

/// Multimodal response engine: RAG context + joint analysis + voice output.
@MainActor
final class VoiceResponseEngine: ObservableObject {
    @Published var lastSpokenText = ""
    @Published var lastAnalysisSummary = ""
    @Published var isVoiceEnabled = true
    @Published var conversationEntries: [ChatMessage] = []

    private let voiceCoach: VoiceCoach
    private let rag = RAGRetriever.shared
    private var lastResponseTime = Date.distantPast
    private var lastIssueKey = ""
    private let minInterval: TimeInterval = 4.5

    init(voiceCoach: VoiceCoach) {
        self.voiceCoach = voiceCoach
    }

    func processLiveFrame(joints: BodyJoints, metrics: CPRMetrics, scene: CPRSceneAnalysis? = nil) {
        let chestTarget = scene?.patient?.sternumPoint
        let analysis = JointAnalysisEngine.analyze(joints: joints, metrics: metrics, chestTarget: chestTarget)
        lastAnalysisSummary = analysis.nodeSummary

        if scene?.patient != nil {
            lastAnalysisSummary += " | " + L10n.t("patient_label") + " ✓"
        }
        if scene?.rescuer != nil {
            lastAnalysisSummary += " | " + L10n.t("rescuer_label") + " ✓"
        }

        let issueKey = issueFingerprint(metrics: metrics, analysis: analysis)
        let now = Date()

        guard issueKey != "ok" || now.timeIntervalSince(lastResponseTime) > 12 else { return }
        guard now.timeIntervalSince(lastResponseTime) >= minInterval else { return }
        guard issueKey != lastIssueKey || now.timeIntervalSince(lastResponseTime) > 10 else { return }

        let chunks = rag.retrieveForMetrics(metrics, joints: joints)
        let response = buildResponse(metrics: metrics, analysis: analysis, chunks: chunks)

        lastIssueKey = issueKey
        lastResponseTime = now
        lastSpokenText = response

        conversationEntries.append(ChatMessage(role: .coach, text: response, timestamp: now))
        if conversationEntries.count > 30 {
            conversationEntries.removeFirst()
        }

        if isVoiceEnabled {
            // Speech handled by CameraViewModel so feedback is always audible once.
        }
    }

    func respondToQuestion(_ question: String, metrics: CPRMetrics?, joints: BodyJoints?) async -> String {
        let chunks = rag.retrieve(for: question, limit: 5)

        if OnDeviceLLM.isAvailable,
           let onDevice = OnDeviceLLM.respond(question: question, metrics: metrics, joints: joints) {
            if isVoiceEnabled { voiceCoach.speak(onDevice, priority: .normal) }
            return onDevice
        }

        let local = buildLocalAnswer(question: question, chunks: chunks, metrics: metrics)
        if isVoiceEnabled { voiceCoach.speak(local, priority: .normal) }
        return local
    }

    private func buildResponse(metrics: CPRMetrics, analysis: JointAnalysis, chunks: [CPRKnowledgeChunk]) -> String {
        var parts: [String] = []

        if let issue = analysis.alignmentIssue {
            parts.append(issueSpecificAdvice(issue: issue, metrics: metrics))
        } else if metrics.overallQuality == .excellent || metrics.overallQuality == .good {
            parts.append(L10n.t("good_form"))
        } else {
            parts.append(localizedFeedback(for: metrics))
        }

        if let chunk = chunks.first, parts.joined().count < 120 {
            parts.append(chunk.content)
        }

        return parts.joined(separator: " ")
    }

    private func issueSpecificAdvice(issue: String, metrics: CPRMetrics) -> String {
        if issue.contains("left") { return L10n.t("hands_right") }
        if issue.contains("right") { return L10n.t("hands_left") }
        if issue.contains("above") || issue.contains("High") { return L10n.t("move_hands_lower") }
        if issue.contains("below") || issue.contains("Low") { return L10n.t("move_hands_higher") }
        if issue.contains("elbow") || issue.contains("Bent") { return L10n.t("straighten_arms") }
        if issue.contains("shallow") { return L10n.t("push_deeper") }
        if issue.contains("deep") { return L10n.t("push_deeper") }
        if issue.contains("confidence") { return L10n.t("adjust_camera") }
        return localizedFeedback(for: metrics)
    }

    private func localizedFeedback(for metrics: CPRMetrics) -> String {
        if metrics.handPlacement != .centered && metrics.handPlacement != .unknown {
            return L10n.t(JointCPRCoachAnalyzer.placementCorrectionKey(for: metrics.handPlacement))
        }
        if metrics.handPlacement == .unknown {
            return L10n.t("hands_off_position")
        }
        if metrics.depthQuality == .tooShallow { return L10n.t("push_deeper") }
        if metrics.compressionsPerMinute > 0 && metrics.compressionsPerMinute < 100 { return L10n.t("push_faster") }
        if metrics.compressionsPerMinute > 120 { return L10n.t("push_slower") }
        if metrics.depthQuality == .tooShallow { return L10n.t("push_deeper") }
        if metrics.depthQuality == .tooDeep { return L10n.t("push_lighter") }
        if metrics.elbowAngle < CPRGuidelines.targetElbowAngleMin { return L10n.t("straighten_arms") }
        if metrics.recoilQuality == .incomplete { return L10n.t("full_recoil") }
        return L10n.t("good_form")
    }

    private func buildLocalAnswer(question: String, chunks: [CPRKnowledgeChunk], metrics: CPRMetrics?) -> String {
        var parts: [String] = []
        if let metrics {
            parts.append("Live: \(Int(metrics.compressionsPerMinute)) CPM, \(String(format: "%.1f", metrics.estimatedDepthCm)) cm depth, \(metrics.handPlacement.rawValue).")
        }
        parts.append(contentsOf: chunks.prefix(2).map(\.content))
        return parts.joined(separator: " ")
    }

    private func metricsDescription(_ metrics: CPRMetrics?) -> String {
        guard let m = metrics else { return "No live session." }
        return "CPM \(Int(m.compressionsPerMinute)), depth \(String(format: "%.1f", m.estimatedDepthCm))cm, placement \(m.handPlacement.rawValue), elbow \(Int(m.elbowAngle))°, pressure \(Int(m.pressureScore))%"
    }

    private func issueFingerprint(metrics: CPRMetrics, analysis: JointAnalysis) -> String {
        if metrics.handPlacement != .centered { return "critical" }
        if metrics.depthQuality == .tooShallow && metrics.compressionsPerMinute > 20 { return "depth" }
        if metrics.compressionsPerMinute > 0 && (metrics.compressionsPerMinute < 100 || metrics.compressionsPerMinute > 120) { return "rate" }
        if metrics.elbowAngle < CPRGuidelines.targetElbowAngleMin { return "elbow" }
        if metrics.recoilQuality == .incomplete { return "recoil" }
        if metrics.overallQuality == .excellent || metrics.overallQuality == .good { return "ok" }
        return "form"
    }

}
