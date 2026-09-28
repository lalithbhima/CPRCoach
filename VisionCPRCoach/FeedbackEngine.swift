import Foundation

@MainActor
final class FeedbackEngine {
    private var lastMessage = ""
    private var lastChangeTime = Date.distantPast
    private let minMessageInterval: TimeInterval = 1.5

    func localizedMessage(for metrics: CPRMetrics) -> String {
        let key = messageKey(for: metrics)
        return LanguageManager.shared.text(key)
    }

    func message(for metrics: CPRMetrics) -> String {
        throttle(localizedMessage(for: metrics))
    }

    func messageKey(for metrics: CPRMetrics) -> String {
        switch metrics.handPlacement {
        case .tooFarLeft, .tooFarRight:
            return JointCPRCoachAnalyzer.placementCorrectionKey(for: metrics.handPlacement)
        case .tooHigh:
            return "move_hands_lower"
        case .tooLow:
            return "move_hands_higher"
        case .unknown:
            return "hands_off_position"
        case .centered:
            return postureKey(for: metrics)
        }
    }

    private func postureKey(for metrics: CPRMetrics) -> String {
        if metrics.elbowAngle < CPRGuidelines.targetElbowAngleMin { return "straighten_arms" }
        if metrics.depthQuality == .tooShallow { return "push_deeper" }
        if metrics.depthQuality == .tooDeep { return "ease_depth" }
        if metrics.compressionsPerMinute > 0 && metrics.compressionsPerMinute < CPRGuidelines.targetRateMin {
            return "push_faster"
        }
        if metrics.compressionsPerMinute > CPRGuidelines.targetRateMax { return "push_slower" }
        if metrics.depthQuality == .tooShallow { return "push_deeper" }
        if metrics.depthQuality == .tooDeep { return "push_lighter" }
        if metrics.recoilQuality == .incomplete { return "full_recoil" }
        if metrics.compressionsPerMinute == 0 { return "begin_compressions" }
        return "good_form"
    }

    private func throttle(_ candidate: String) -> String {
        let now = Date()
        if candidate != lastMessage || now.timeIntervalSince(lastChangeTime) > minMessageInterval {
            lastMessage = candidate
            lastChangeTime = now
        }
        return lastMessage
    }
}
