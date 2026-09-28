import Foundation

/// Legacy facade — routes to built-in CPR voice engine.
@MainActor
enum OnDeviceLLM {
    static var isAvailable: Bool { BuiltInCPRVoiceEngine.shared.isReady }

    static func respond(
        question: String,
        metrics: CPRMetrics? = nil,
        joints: BodyJoints? = nil
    ) -> String? {
        try? BuiltInCPRVoiceEngine.shared.respond(to: question, metrics: metrics, joints: joints)
    }
}
