import Foundation

/// AHA-aligned CPR quality targets (2020 AHA Guidelines).
enum CPRGuidelines {
    static let targetRateMin = 100.0
    static let targetRateMax = 120.0
    static let targetDepthMinCm = 5.0
    static let targetDepthMaxCm = 6.0
    static let targetElbowAngleMin = 165.0
    /// Slightly relaxed threshold during the 10-second setup window.
    static let setupElbowAngleMin = 158.0
    static let handCenterTolerance = 0.08
    /// Normalized chest compression band on patient torso (Vision space, origin bottom-left).
    static let chestBandLowerFraction = 0.44
    static let chestBandUpperFraction = 0.76
    static let chestHorizontalInsetFraction = 0.22
    /// Margins so coaching only fires when rate/depth are clearly out of AHA range.
    static let rateCoachBelowMin = 95.0
    static let rateCoachAboveMax = 125.0
    static let depthCoachBelowMinCm = 4.6
    static let depthCoachAboveMaxCm = 6.4
    static let minRateConfidence = 0.55
    static let minDepthConfidence = 0.55
    static let minReliableCPM = 18.0
    static let minRecoilRatio = 0.65
    static let compressionDutyCycle = 0.50
    /// Fine-tune only — keeps displayed rate near true 100–120 CPM (not too fast/slow coaching).
    static let rateMeasurementScale = 1.04
    static let depthMeasurementScale = 1.08
    /// Maps torso-normalized wrist travel to centimeters.
    static let depthTorsoReferenceCm = 5.5

    static let emergencyNumberUS = "911"

    static let disclaimer =
        "Vision CPR Coach provides training guidance only. It is not a medical device and does not diagnose conditions. In an emergency, call \(emergencyNumberUS) immediately."
}

enum CompressionQuality: String {
    case excellent = "Excellent"
    case good = "Good"
    case needsWork = "Needs Work"
    case poor = "Poor"
    case unknown = "Analyzing"
}

enum DepthEstimate: String {
    case adequate = "Adequate (~5–6 cm)"
    case tooShallow = "Too Shallow"
    case tooDeep = "Too Deep"
    case unknown = "Estimating"
}

enum RecoilQuality: String {
    case full = "Full Recoil"
    case incomplete = "Incomplete Recoil"
    case unknown = "Analyzing"
}
