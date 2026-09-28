import Foundation

@MainActor
final class CPRSessionAnalysisService {
    static let shared = CPRSessionAnalysisService()

    private let llm = OpenRouterLLMEngine.shared

    func ruleBasedSummary(session: CPRPracticeSession, priorSessions: [CPRPracticeSession]) -> String {
        var parts: [String] = []

        let rateOK = session.averageCPM >= CPRGuidelines.targetRateMin && session.averageCPM <= CPRGuidelines.targetRateMax
        let depthOK = session.averageDepthCm >= CPRGuidelines.targetDepthMinCm && session.averageDepthCm <= CPRGuidelines.targetDepthMaxCm

        if rateOK {
            parts.append("Compression rate stayed within the 100–120 CPM target range.")
        } else if session.averageCPM > 0 {
            parts.append(session.averageCPM < CPRGuidelines.targetRateMin
                ? "Compression rate was below the recommended 100–120 CPM range."
                : "Compression rate ran above the recommended 100–120 CPM range.")
        }

        if depthOK {
            parts.append("Estimated depth was near the 5–6 cm guideline.")
        } else if session.averageDepthCm > 0 {
            parts.append(session.averageDepthCm < CPRGuidelines.targetDepthMinCm
                ? "Depth was inconsistent and often too shallow."
                : "Depth occasionally exceeded the upper guideline — ease force slightly.")
        }

        let handsPct = Int(session.handsOnTargetPercentage * 100)
        parts.append("Hands were on the chest target about \(handsPct)% of tracked frames.")

        if session.elbowLockAccuracy < 0.7 {
            parts.append("Elbows bent during several compression cycles — stack shoulders over hands.")
        }

        if session.recoilAccuracy < 0.7 {
            parts.append("Allow fuller chest recoil between compressions.")
        }

        if let delta = priorSessions.dropFirst().first.map({ session.overallScore - $0.overallScore }),
           priorSessions.count > 1 {
            if delta > 3 {
                parts.append(String(format: "Overall score improved %.0f points from your previous session.", delta))
            } else if delta < -3 {
                parts.append("Compared to your last session, form dipped slightly — review the main fix below.")
            }
        }

        let tip = LanguageManager.shared.text(session.improvementSuggestionKey)
        parts.append("Focus next: \(tip)")

        return parts.joined(separator: " ")
    }

    func generateAISummary(
        session: CPRPracticeSession,
        priorSessions: [CPRPracticeSession]
    ) async -> String {
        let fallback = ruleBasedSummary(session: session, priorSessions: priorSessions)

        guard llm.isConfigured else { return fallback }

        let priorContext: String
        if priorSessions.isEmpty {
            priorContext = "This is the user's first saved practice session."
        } else {
            let lines = priorSessions.prefix(5).enumerated().map { index, s in
                "Session \(index + 1): score \(Int(s.overallScore))%, rate \(Int(s.averageCPM)) CPM, depth \(String(format: "%.1f", s.averageDepthCm)) cm"
            }
            priorContext = "Prior sessions (newest first):\n" + lines.joined(separator: "\n")
        }

        let bestFrame = session.frames.max(by: { $0.pressureScore < $1.pressureScore })
        let worstFrame = session.frames.min(by: { $0.pressureScore < $1.pressureScore })

        let prompt = """
        Analyze this CPR practice session for a training app. Write 3–5 sentences in plain, encouraging language.
        Mention rate, depth, hand placement, elbows, and recoil. End with one concrete focus for next time.
        Do not diagnose medical conditions. Do not cite AHA or Red Cross.

        Session duration: \(session.formattedDuration)
        Overall score: \(Int(session.overallScore))%
        Average CPM: \(Int(session.averageCPM)) (best \(Int(session.bestCPM)))
        Average depth: \(String(format: "%.1f", session.averageDepthCm)) cm
        Depth consistency: \(Int(session.depthConsistency * 100))%
        Hand placement accuracy: \(Int(session.handPlacementAccuracy * 100))%
        Elbow lock accuracy: \(Int(session.elbowLockAccuracy * 100))%
        Recoil accuracy: \(Int(session.recoilAccuracy * 100))%
        Hands on chest target: \(Int(session.handsOnTargetPercentage * 100))%
        Calibration used: \(session.calibrationWasUsed ? "yes" : "no")
        Main issue key: \(session.mainMistakeKey)

        \(priorContext)

        Best moment (highest pressure score): \(bestFrame.map { "t=\(String(format: "%.1f", $0.timestamp))s, CPM=\(Int($0.cpm)), depth=\(String(format: "%.1f", $0.depthCm))cm" } ?? "n/a")
        Weakest moment: \(worstFrame.map { "t=\(String(format: "%.1f", $0.timestamp))s, CPM=\(Int($0.cpm)), depth=\(String(format: "%.1f", $0.depthCm))cm" } ?? "n/a")
        """

        do {
            let lang = LanguageManager.shared
            let system = [
                lang.text("progress_analysis_system_prompt"),
                lang.textFormat("llm_reply_language", lang.current.name, lang.current.name)
            ].joined(separator: "\n\n")
            return try await llm.completeOnce(
                system: system,
                user: prompt,
                maxTokens: 320
            )
        } catch {
            return fallback
        }
    }
}
