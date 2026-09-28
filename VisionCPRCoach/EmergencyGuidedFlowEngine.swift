import Foundation

/// Phone-dispatcher style guided CPR flow: speak a step → listen → branch → next step.
@MainActor
final class EmergencyGuidedFlowEngine {
    enum Step: String {
        case confirmEmergency
        case victimAge
        case sceneSafe
        case checkResponsive
        case checkBreathing
        case call911
        case confirm911
        case getAED
        case startCPR
        case activeCoaching
        case recoveryMonitor
        case notEmergency
    }

    enum VictimAge: String {
        case infant, child, adult
    }

    struct Turn {
        let speech: String
        let step: Step
        let flowState: CPRFlowState
        let sessionEnded: Bool
        /// When true, guided procedure is finished — active CPR coaching uses OpenRouter instead of repeating scripts.
        let useOpenRouter: Bool

        init(
            speech: String,
            step: Step,
            flowState: CPRFlowState,
            sessionEnded: Bool,
            useOpenRouter: Bool = false
        ) {
            self.speech = speech
            self.step = step
            self.flowState = flowState
            self.sessionEnded = sessionEnded
            self.useOpenRouter = useOpenRouter
        }
    }

    private(set) var step: Step = .confirmEmergency
    private(set) var victimAge: VictimAge = .adult
    private(set) var isEmergency = false
    private(set) var isResponsive: Bool?
    private(set) var isBreathingNormally: Bool?
    private(set) var called911 = false
    private var retryCount = 0
    private var coachingPulse = 0

    func reset() {
        step = .confirmEmergency
        victimAge = .adult
        isEmergency = false
        isResponsive = nil
        isBreathingNormally = nil
        called911 = false
        retryCount = 0
        coachingPulse = 0
    }

    /// First thing spoken when Voice AI starts.
    func openingTurn() -> Turn {
        reset()
        return speak(key: "guided_opening", step: .confirmEmergency, flow: .ready)
    }

    /// Process what the user said and return the coach's next line.
    func advance(
        userInput: String,
        metrics: CPRMetrics?,
        joints: BodyJoints?
    ) -> Turn {
        let text = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        coachingPulse += 1

        switch step {
        case .confirmEmergency:
            return handleConfirmEmergency(text)
        case .victimAge:
            return handleVictimAge(text)
        case .sceneSafe:
            return handleSceneSafe(text)
        case .checkResponsive:
            return handleCheckResponsive(text)
        case .checkBreathing:
            return handleCheckBreathing(text)
        case .call911:
            return handleCall911(text)
        case .confirm911:
            return handleConfirm911(text)
        case .getAED:
            return handleGetAED(text)
        case .startCPR:
            return handleStartCPR(text, metrics: metrics, joints: joints)
        case .activeCoaching:
            return handleActiveCoaching(text, metrics: metrics, joints: joints)
        case .recoveryMonitor:
            return handleRecoveryMonitor(text)
        case .notEmergency:
            return speak(key: "guided_not_emergency", step: .notEmergency, flow: .finished, ended: true)
        }
    }

    func summarizeSession() -> String {
        var parts: [String] = []
        parts.append(victimAge.rawValue.capitalized)
        if isResponsive == true { parts.append("responsive") }
        if isResponsive == false { parts.append("unresponsive") }
        if isBreathingNormally == false { parts.append("not breathing normally") }
        if called911 { parts.append("911 contacted") }
        if step == .activeCoaching || step == .startCPR {
            parts.append("CPR in progress")
        }
        let detail = parts.joined(separator: ", ")
        return String(format: LanguageManager.shared.text("guided_summary"), detail)
    }

    // MARK: - Step handlers

    private func handleConfirmEmergency(_ text: String) -> Turn {
        if matchesNo(text) {
            step = .notEmergency
            return speak(key: "guided_not_emergency", step: .notEmergency, flow: .finished, ended: true)
        }
        if matchesYes(text) || mentionsEmergency(text) {
            isEmergency = true
            retryCount = 0
            step = .victimAge
            return speak(key: "guided_ask_age", step: .victimAge, flow: .ready)
        }
        return retry(key: "guided_confirm_emergency_retry", step: .confirmEmergency, flow: .ready)
    }

    private func handleVictimAge(_ text: String) -> Turn {
        if let age = parseVictimAge(text) {
            victimAge = age
            retryCount = 0
            step = .sceneSafe
            return speak(key: "guided_scene_safe", step: .sceneSafe, flow: .checkResponsiveness)
        }
        return retry(key: "guided_ask_age_retry", step: .victimAge, flow: .ready)
    }

    private func handleSceneSafe(_ text: String) -> Turn {
        retryCount = 0
        step = .checkResponsive
        return speak(key: "guided_check_responsive", step: .checkResponsive, flow: .checkResponsiveness)
    }

    private func handleCheckResponsive(_ text: String) -> Turn {
        if mentionsNotBreathing(text) {
            isResponsive = false
            isBreathingNormally = false
            retryCount = 0
            step = .call911
            return speak(key: "guided_call911_urgent", step: .call911, flow: .callEmergency)
        }
        if matchesYes(text) || mentionsResponsive(text) {
            isResponsive = true
            retryCount = 0
            step = .checkBreathing
            return speak(key: "guided_check_breathing_responsive", step: .checkBreathing, flow: .checkBreathing)
        }
        if matchesNo(text) || mentionsUnresponsive(text) {
            isResponsive = false
            retryCount = 0
            step = .checkBreathing
            return speak(key: "guided_check_breathing", step: .checkBreathing, flow: .checkBreathing)
        }
        return retry(key: "guided_check_responsive_retry", step: .checkResponsive, flow: .checkResponsiveness)
    }

    private func handleCheckBreathing(_ text: String) -> Turn {
        if matchesYes(text) && !mentionsGasping(text) && !mentionsNotBreathing(text) {
            isBreathingNormally = true
            retryCount = 0
            step = .recoveryMonitor
            return speak(key: "guided_breathing_ok", step: .recoveryMonitor, flow: .finished)
        }
        if matchesNo(text) || mentionsNotBreathing(text) || mentionsGasping(text) || matchesUnsure(text) {
            isBreathingNormally = false
            retryCount = 0
            step = .call911
            let key = isResponsive == true ? "guided_call911_worsening" : "guided_call911_urgent"
            return speak(key: key, step: .call911, flow: .callEmergency)
        }
        return retry(key: "guided_check_breathing_retry", step: .checkBreathing, flow: .checkBreathing)
    }

    private func handleCall911(_ text: String) -> Turn {
        if matchesCantCall(text) {
            step = .startCPR
            return speak(key: cprStartKey(), step: .startCPR, flow: .startCompressions)
        }
        if matchesYes(text) || mentionsCalled911(text) {
            called911 = true
            retryCount = 0
            step = .getAED
            return speak(key: "guided_get_aed", step: .getAED, flow: .callEmergency)
        }
        step = .confirm911
        return speak(key: "guided_confirm_911", step: .confirm911, flow: .callEmergency)
    }

    private func handleConfirm911(_ text: String) -> Turn {
        if matchesYes(text) || mentionsCalled911(text) {
            called911 = true
            retryCount = 0
            step = .getAED
            return speak(key: "guided_get_aed", step: .getAED, flow: .callEmergency)
        }
        if matchesNo(text) {
            return speak(key: "guided_call911_now", step: .confirm911, flow: .callEmergency)
        }
        return retry(key: "guided_confirm_911_retry", step: .confirm911, flow: .callEmergency)
    }

    private func handleGetAED(_ text: String) -> Turn {
        retryCount = 0
        step = .startCPR
        return speak(key: cprStartKey(), step: .startCPR, flow: .startCompressions)
    }

    private func handleStartCPR(_ text: String, metrics: CPRMetrics?, joints: BodyJoints?) -> Turn {
        retryCount = 0
        step = .activeCoaching
        let coaching = liveCoachingLine(metrics: metrics, joints: joints)
        let base = LanguageManager.shared.text("guided_cpr_active")
        let speech = coaching.isEmpty ? base : "\(base) \(coaching)"
        return Turn(speech: speech, step: .activeCoaching, flowState: .activeCoaching, sessionEnded: false)
    }

    private func handleActiveCoaching(_ text: String, metrics: CPRMetrics?, joints: BodyJoints?) -> Turn {
        if mentionsStopCPR(text) || mentionsResponsive(text) || matchesYes(text) && mentionsBreathing(text) {
            step = .recoveryMonitor
            return speak(key: "guided_recovery_check", step: .recoveryMonitor, flow: .finished)
        }

        // Guided procedure is complete — stop repeating push/keep-going scripts; coach via OpenRouter.
        return Turn(
            speech: "",
            step: .activeCoaching,
            flowState: .activeCoaching,
            sessionEnded: false,
            useOpenRouter: true
        )
    }

    private func handleRecoveryMonitor(_ text: String) -> Turn {
        if isQuestion(text) {
            let answer = (try? BuiltInCPRVoiceEngine.shared.respond(to: text, metrics: nil, joints: nil))
                ?? LanguageManager.shared.text("guided_recovery_stay")
            return Turn(speech: answer, step: .recoveryMonitor, flowState: .finished, sessionEnded: false)
        }
        return speak(key: "guided_recovery_stay", step: .recoveryMonitor, flow: .finished)
    }

    // MARK: - Speech helpers

    private func speak(key: String, step: Step, flow: CPRFlowState, ended: Bool = false) -> Turn {
        self.step = step
        retryCount = 0
        return Turn(
            speech: LanguageManager.shared.text(key),
            step: step,
            flowState: flow,
            sessionEnded: ended
        )
    }

    private func retry(key: String, step: Step, flow: CPRFlowState) -> Turn {
        retryCount += 1
        if retryCount >= 3 {
            retryCount = 0
            return speak(key: "guided_unclear_help", step: step, flow: flow)
        }
        return Turn(
            speech: LanguageManager.shared.text(key),
            step: step,
            flowState: flow,
            sessionEnded: false
        )
    }

    private func cprStartKey() -> String {
        switch victimAge {
        case .infant: return "guided_start_cpr_infant"
        case .child: return "guided_start_cpr_child"
        case .adult: return "guided_start_cpr_adult"
        }
    }

    private func liveCoachingLine(metrics: CPRMetrics?, joints: BodyJoints?) -> String {
        guard let m = metrics, m.compressionsPerMinute > 8 else {
            return LanguageManager.shared.text("guided_push_now")
        }
        if m.compressionsPerMinute < 100 { return LanguageManager.shared.text("voice_live_rate_slow") }
        if m.compressionsPerMinute > 120 { return LanguageManager.shared.text("voice_live_rate_fast") }
        if m.depthQuality == .tooShallow { return LanguageManager.shared.text("voice_live_depth_shallow") }
        if m.handPlacement != .centered && m.handPlacement != .unknown {
            return LanguageManager.shared.text("voice_live_hands_adjust")
        }
        if m.recoilQuality == .incomplete { return LanguageManager.shared.text("voice_live_recoil") }
        if m.elbowAngle < CPRGuidelines.targetElbowAngleMin { return LanguageManager.shared.text("voice_live_elbows") }
        if m.overallQuality == .excellent || m.overallQuality == .good {
            return LanguageManager.shared.text("guided_good_cpr")
        }
        return String(format: LanguageManager.shared.text("voice_live_rate_ok"), Int(m.compressionsPerMinute))
    }

    // MARK: - NLP helpers (English + localized tokens; flow sequence unchanged)

    private func normalized(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols))
        return stripped.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: LanguageManager.shared.locale
        )
    }

    private func tokens(_ key: String, fallback: [String]) -> [String] {
        Array(Set(fallback + LanguageManager.shared.nlpTokens(key)))
    }

    private func containsAny(_ text: String, in tokenList: [String]) -> Bool {
        let q = normalized(text)
        return tokenList.contains { token in
            let t = normalized(token)
            return !t.isEmpty && q.contains(t)
        }
    }

    private func parseVictimAge(_ text: String) -> VictimAge? {
        if containsAny(text, in: tokens("nlp_infant", fallback: ["infant", "baby", "newborn"])) { return .infant }
        if containsAny(text, in: tokens("nlp_child", fallback: ["child", "kid", "toddler", "boy", "girl"])) { return .child }
        if containsAny(text, in: tokens("nlp_adult", fallback: ["adult", "man", "woman", "grown", "teen", "teenager", "elderly"])) { return .adult }
        return nil
    }

    private func matchesYes(_ text: String) -> Bool {
        containsAny(text, in: tokens("nlp_yes", fallback: ["yes", "yeah", "yep", "yup", "correct", "affirmative", "sure", "ok", "okay", "done", "ready", "i did", "called"]))
    }

    private func matchesNo(_ text: String) -> Bool {
        let list = tokens("nlp_no", fallback: ["no", "nope", "nah", "negative"])
        let q = normalized(text)
        if list.contains(where: { normalized($0) == q }) { return true }
        return list.contains { token in
            let t = normalized(token)
            guard !t.isEmpty else { return false }
            if t.count <= 3 {
                return q == t || q.hasPrefix("\(t) ") || q.hasSuffix(" \(t)") || q.contains(" \(t) ")
            }
            return q.contains(t)
        }
    }

    private func matchesUnsure(_ text: String) -> Bool {
        containsAny(text, in: tokens("nlp_unsure", fallback: ["unsure", "don't know", "not sure", "i don't know", "can't tell"]))
    }

    private func mentionsEmergency(_ text: String) -> Bool {
        containsAny(text, in: tokens("nlp_emergency", fallback: ["emergency", "help", "collapsed", "unconscious", "cardiac", "heart attack"]))
            || mentionsNotBreathing(text)
    }

    private func mentionsResponsive(_ text: String) -> Bool {
        containsAny(text, in: tokens("nlp_responsive", fallback: ["responding", "responded", "woke", "moving", "answered", "eyes open", "conscious"]))
    }

    private func mentionsUnresponsive(_ text: String) -> Bool {
        containsAny(text, in: tokens("nlp_unresponsive", fallback: ["unresponsive", "not responding", "won't wake", "no response", "passed out", "collapsed", "unconscious"]))
    }

    private func mentionsBreathing(_ text: String) -> Bool {
        containsAny(text, in: tokens("nlp_breathing", fallback: ["breath", "breathing"]))
    }

    private func mentionsNotBreathing(_ text: String) -> Bool {
        containsAny(text, in: tokens("nlp_not_breathing", fallback: ["not breathing", "no breathing", "stopped breathing", "isn't breathing", "aren't breathing"]))
    }

    private func mentionsGasping(_ text: String) -> Bool {
        containsAny(text, in: tokens("nlp_gasping", fallback: ["gasp", "gasping"]))
    }

    private func mentionsCalled911(_ text: String) -> Bool {
        containsAny(text, in: tokens("nlp_called_ems", fallback: ["called", "on the phone", "on the line", "911", "999", "112", "dispatch", "ambulance", "emergency"]))
    }

    private func matchesCantCall(_ text: String) -> Bool {
        containsAny(text, in: tokens("nlp_cant_call", fallback: ["can't call", "cannot call", "no phone", "alone", "by myself"]))
    }

    private func mentionsStopCPR(_ text: String) -> Bool {
        containsAny(text, in: tokens("nlp_stop_cpr", fallback: ["stop cpr", "should i stop", "they woke", "started breathing", "responsive again"]))
    }

    private func isQuestion(_ text: String) -> Bool {
        if text.contains("?") || text.contains("？") { return true }
        let q = normalized(text)
        return tokens("nlp_question", fallback: ["what", "how", "why", "when", "where", "should", "can ", "do i", "is it", "am i"])
            .contains { q.hasPrefix(normalized($0)) }
    }
}
