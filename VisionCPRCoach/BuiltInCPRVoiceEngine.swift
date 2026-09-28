import Foundation

/// Built-in conversational CPR voice engine. Always ready — no download, no API.
/// Uses AHA-grounded RAG + natural language synthesis so answers feel human and vary each turn.
@MainActor
final class BuiltInCPRVoiceEngine {
    static let shared = BuiltInCPRVoiceEngine()

    @MainActor
    enum EngineError: LocalizedError {
        case emptyQuestion

        var errorDescription: String? {
            switch self {
            case .emptyQuestion:
                return LanguageManager.shared.text("voice_llm_empty")
            }
        }
    }

    private let rag = RAGRetriever.shared
    private var history: [(user: String, coach: String, topic: String)] = []
    private var turnCount = 0

    var isReady: Bool { true }

    var statusMessage: String {
        LanguageManager.shared.text("voice_ai_ready")
    }

    func resetSession() {
        history.removeAll()
        turnCount = 0
    }

    func respond(
        to userMessage: String,
        metrics: CPRMetrics?,
        joints: BodyJoints?
    ) throws -> String {
        let question = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { throw EngineError.emptyQuestion }

        let intent = classifyIntent(question)
        let searchQuery = expandedSearchQuery(question: question, intent: intent)
        let chunks = rag.retrieve(for: searchQuery, limit: 5)

        let reply = composeNaturalReply(
            question: question,
            intent: intent,
            chunks: chunks,
            metrics: metrics,
            joints: joints
        )

        history.append((user: question, coach: reply, topic: intent.rawValue))
        if history.count > 8 { history.removeFirst() }
        turnCount += 1

        return reply
    }

    func summarizeConversation(_ log: [ChatMessage]) -> String {
        let userTurns = log.filter { $0.role == .user }
        guard !userTurns.isEmpty else {
            return LanguageManager.shared.text("emergency_summary_empty")
        }

        let topics = userTurns.map { classifyIntent($0.text).label }
        let uniqueTopics = Array(NSOrderedSet(array: topics)) as? [String] ?? topics
        let topicList = uniqueTopics.prefix(3).joined(separator: ", ")

        let lastCoach = log.last(where: { $0.role == .coach })?.text ?? ""
        let keyPoint = lastCoach.split(separator: ".").first.map(String.init) ?? lastCoach

        return String(
            format: LanguageManager.shared.text("emergency_summary_local"),
            topicList,
            keyPoint
        )
    }

    // MARK: - Intent

    private enum CPRIntent: String {
        case emergency911, breathing, responsiveness, hands, rate, depth, recoil
        case technique, whenToStart, aed, infant, child, choking, fatigue, recovery
        case compressionOnly, sceneSafety, quality, interruptions, bystander, stopCPR, general

        var label: String {
            switch self {
            case .emergency911: return "calling 911"
            case .breathing: return "breathing check"
            case .responsiveness: return "responsiveness"
            case .hands: return "hand placement"
            case .rate: return "compression rate"
            case .depth: return "compression depth"
            case .recoil: return "chest recoil"
            case .technique: return "CPR technique"
            case .whenToStart: return "when to start CPR"
            case .aed: return "AED use"
            case .infant: return "infant CPR"
            case .child: return "child CPR"
            case .choking: return "choking"
            case .fatigue: return "rescuer fatigue"
            case .recovery: return "recovery"
            case .compressionOnly: return "hands-only CPR"
            case .sceneSafety: return "scene safety"
            case .quality: return "CPR quality"
            case .interruptions: return "minimizing pauses"
            case .bystander: return "bystander CPR"
            case .stopCPR: return "stopping CPR"
            case .general: return "CPR guidance"
            }
        }

        var retrievalBoost: String {
            switch self {
            case .emergency911: return "911 emergency call ambulance AED dispatch"
            case .breathing: return "breathing gasping agonal normal breath check"
            case .responsiveness: return "responsive unresponsive tap shoulder conscious"
            case .hands: return "hand placement sternum center chest heel"
            case .rate: return "compression rate 100 120 per minute rhythm fast slow"
            case .depth: return "compression depth 5cm 2 inches shallow deep push hard"
            case .recoil: return "chest recoil full release lean bounce"
            case .technique: return "elbow straight shoulders posture body weight form"
            case .whenToStart: return "when start CPR unresponsive not breathing cardiac arrest"
            case .aed: return "AED defibrillator pads shock device"
            case .infant: return "infant baby newborn CPR two fingers"
            case .child: return "child pediatric CPR compressions"
            case .choking: return "choking obstruction blocked airway heimlich"
            case .fatigue: return "tired fatigue switch rescuer rotate two minutes"
            case .recovery: return "recovery position responsive breathing wake stop"
            case .compressionOnly: return "compression only hands only no breaths"
            case .sceneSafety: return "scene safe danger environment approach"
            case .quality: return "quality metrics high quality CPR survival"
            case .interruptions: return "pause interruption minimize stop compressions"
            case .bystander: return "bystander witness fear help afraid"
            case .stopCPR: return "stop CPR when responsive breathing EMS arrives"
            case .general: return "CPR emergency cardiac arrest compressions 911"
            }
        }
    }

    private func classifyIntent(_ question: String) -> CPRIntent {
        let q = question.lowercased()

        let rules: [(CPRIntent, [String])] = [
            (.emergency911, ["911", "ambulance", "emergency number", "call who", "phone", "dispatch"]),
            (.stopCPR, ["stop cpr", "when to stop", "should i stop", "do i stop", "they woke", "started breathing"]),
            (.recovery, ["recovery position", "wake up", "woke up", "responsive again", "side position"]),
            (.aed, ["aed", "defibrillator", "shock", "pads", "device"]),
            (.choking, ["choking", "choke", "blocked", "heimlich", "object stuck"]),
            (.infant, ["infant", "baby", "newborn"]),
            (.child, ["child", "kid", "pediatric", "toddler"]),
            (.breathing, ["breathing", "breath", "gasp", "agonal", "not breathing", "airway"]),
            (.responsiveness, ["responsive", "unresponsive", "conscious", "wake", "respond"]),
            (.hands, ["hand", "hands", "placement", "where do i put", "position my hands", "sternum"]),
            (.rate, ["rate", "speed", "fast", "slow", "too fast", "too slow", "cpm", "per minute", "rhythm"]),
            (.depth, ["depth", "deep", "shallow", "hard enough", "how hard", "push down", "inches", "cm"]),
            (.recoil, ["recoil", "release", "leaning", "bounce back", "come up"]),
            (.technique, ["elbow", "arm", "straight", "posture", "kneel", "position my body", "form"]),
            (.whenToStart, ["when do i start", "should i start", "begin cpr", "start compressions", "collapsed"]),
            (.fatigue, ["tired", "fatigue", "exhausted", "switch", "rotate", "can't continue"]),
            (.compressionOnly, ["mouth to mouth", "rescue breath", "breaths", "hands only", "compression only"]),
            (.sceneSafety, ["safe", "danger", "scene"]),
            (.interruptions, ["pause", "stop compressions", "interrupt", "break"]),
            (.bystander, ["afraid", "scared", "liability", "wrong", "hurt them", "bystander"]),
            (.quality, ["quality", "good cpr", "doing it right", "am i doing"])
        ]

        for (intent, keywords) in rules {
            if keywords.contains(where: { q.contains($0) }) {
                return intent
            }
        }

        if isFollowUp(question) {
            return CPRIntent(rawValue: history.last?.topic ?? "") ?? .general
        }

        return .general
    }

    private func isFollowUp(_ question: String) -> Bool {
        let q = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cues = ["and ", "what about", "how about", "also ", "what if", "should i", "do i", "can i", "how do i"]
        return cues.contains(where: { q.hasPrefix($0) }) || q.split(separator: " ").count <= 4
    }

    private func expandedSearchQuery(question: String, intent: CPRIntent) -> String {
        var parts = [question, intent.retrievalBoost]
        if isFollowUp(question), let last = history.last {
            parts.append(last.user)
            parts.append(last.coach)
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Natural synthesis

    private func composeNaturalReply(
        question: String,
        intent: CPRIntent,
        chunks: [CPRKnowledgeChunk],
        metrics: CPRMetrics?,
        joints: BodyJoints?
    ) -> String {
        let primary = chunks.first?.content ?? CPRKnowledgeBase.chunks[0].content
        let secondary = chunks.dropFirst().first?.content
        let opener = pickOpener(intent: intent, question: question)
        let live = liveCoachingNote(metrics: metrics, joints: joints, intent: intent)
        let reassurance = pickReassurance(intent: intent)
        let urgent911 = needs911Reminder(question: question, intent: intent)

        let body: String
        switch turnCount % 5 {
        case 0:
            body = [opener, primary, live, reassurance].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        case 1:
            body = [opener, primary, secondary].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        case 2:
            body = [primary, live, reassurance].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        case 3:
            body = [opener, secondary ?? primary, primary].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        default:
            body = [opener, primary].joined(separator: " ")
        }

        var result = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if urgent911, !result.lowercased().contains("911") {
            result += " " + LanguageManager.shared.text("emergency_911_reminder")
        }
        return result
    }

    private func pickOpener(intent: CPRIntent, question: String) -> String {
        let q = question.lowercased()
        let keys: [String]
        if q.contains("?") {
            keys = ["voice_opener_question_1", "voice_opener_question_2", "voice_opener_question_3"]
        } else if isFollowUp(question) {
            keys = ["voice_opener_followup_1", "voice_opener_followup_2"]
        } else if intent == .emergency911 || intent == .whenToStart {
            keys = ["voice_opener_urgent_1", "voice_opener_urgent_2"]
        } else {
            keys = ["voice_opener_calm_1", "voice_opener_calm_2", "voice_opener_calm_3"]
        }
        return LanguageManager.shared.text(keys[turnCount % keys.count])
    }

    private func pickReassurance(intent: CPRIntent) -> String? {
        guard intent == .bystander || intent == .whenToStart || intent == .general else { return nil }
        let keys = ["voice_reassure_1", "voice_reassure_2"]
        return turnCount.isMultiple(of: 2) ? LanguageManager.shared.text(keys[turnCount % keys.count]) : nil
    }

    private func liveCoachingNote(metrics: CPRMetrics?, joints: BodyJoints?, intent: CPRIntent) -> String? {
        guard let m = metrics, m.compressionsPerMinute > 10 else { return nil }

        switch intent {
        case .rate:
            if m.compressionsPerMinute < 100 {
                return LanguageManager.shared.text("voice_live_rate_slow")
            }
            if m.compressionsPerMinute > 120 {
                return LanguageManager.shared.text("voice_live_rate_fast")
            }
            return String(format: LanguageManager.shared.text("voice_live_rate_ok"), Int(m.compressionsPerMinute))
        case .depth:
            if m.depthQuality == .tooShallow {
                return LanguageManager.shared.text("voice_live_depth_shallow")
            }
            if m.depthQuality == .tooDeep {
                return LanguageManager.shared.text("voice_live_depth_deep")
            }
            return String(format: LanguageManager.shared.text("voice_live_depth_ok"), m.estimatedDepthCm)
        case .hands:
            if m.handPlacement != .centered && m.handPlacement != .unknown {
                return LanguageManager.shared.text("voice_live_hands_adjust")
            }
        case .recoil:
            if m.recoilQuality == .incomplete {
                return LanguageManager.shared.text("voice_live_recoil")
            }
        case .technique:
            if m.elbowAngle < CPRGuidelines.targetElbowAngleMin {
                return LanguageManager.shared.text("voice_live_elbows")
            }
        default:
            break
        }

        if let joints, joints.averageConfidence < 0.35 {
            return LanguageManager.shared.text("voice_live_camera")
        }
        return nil
    }

    private func needs911Reminder(question: String, intent: CPRIntent) -> Bool {
        if intent == .emergency911 || intent == .whenToStart { return false }
        let q = question.lowercased()
        let urgent = ["911", "unconscious", "not breathing", "cardiac", "emergency", "collapsed", "arrest"]
        return urgent.contains { q.contains($0) }
    }
}
