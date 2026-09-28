import Foundation

struct CPRFrameMetric: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Double
    let cpm: Double
    let depthCm: Double
    let elbowAngle: Double
    let handPlacementScore: Double
    let recoilScore: Double
    let handsOnTarget: Bool
    let pressureScore: Double

    // Full live-metrics snapshot (training archive)
    let handPlacement: String
    let motionAmplitude: Double
    let depthQuality: String
    let recoilQuality: String
    let overallQuality: String
    let confidence: Double
    let compressionActive: Bool
    let rateConfidence: Double
    let depthConfidence: Double

    init(
        id: UUID,
        timestamp: Double,
        cpm: Double,
        depthCm: Double,
        elbowAngle: Double,
        handPlacementScore: Double,
        recoilScore: Double,
        handsOnTarget: Bool,
        pressureScore: Double,
        handPlacement: String = "Unknown",
        motionAmplitude: Double = 0,
        depthQuality: String = "Unknown",
        recoilQuality: String = "Unknown",
        overallQuality: String = "Unknown",
        confidence: Double = 0,
        compressionActive: Bool = false,
        rateConfidence: Double = 0,
        depthConfidence: Double = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.cpm = cpm
        self.depthCm = depthCm
        self.elbowAngle = elbowAngle
        self.handPlacementScore = handPlacementScore
        self.recoilScore = recoilScore
        self.handsOnTarget = handsOnTarget
        self.pressureScore = pressureScore
        self.handPlacement = handPlacement
        self.motionAmplitude = motionAmplitude
        self.depthQuality = depthQuality
        self.recoilQuality = recoilQuality
        self.overallQuality = overallQuality
        self.confidence = confidence
        self.compressionActive = compressionActive
        self.rateConfidence = rateConfidence
        self.depthConfidence = depthConfidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Double.self, forKey: .timestamp)
        cpm = try container.decode(Double.self, forKey: .cpm)
        depthCm = try container.decode(Double.self, forKey: .depthCm)
        elbowAngle = try container.decode(Double.self, forKey: .elbowAngle)
        handPlacementScore = try container.decode(Double.self, forKey: .handPlacementScore)
        recoilScore = try container.decode(Double.self, forKey: .recoilScore)
        handsOnTarget = try container.decode(Bool.self, forKey: .handsOnTarget)
        pressureScore = try container.decode(Double.self, forKey: .pressureScore)
        handPlacement = try container.decodeIfPresent(String.self, forKey: .handPlacement) ?? "Unknown"
        motionAmplitude = try container.decodeIfPresent(Double.self, forKey: .motionAmplitude) ?? 0
        depthQuality = try container.decodeIfPresent(String.self, forKey: .depthQuality) ?? "Unknown"
        recoilQuality = try container.decodeIfPresent(String.self, forKey: .recoilQuality) ?? "Unknown"
        overallQuality = try container.decodeIfPresent(String.self, forKey: .overallQuality) ?? "Unknown"
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
        compressionActive = try container.decodeIfPresent(Bool.self, forKey: .compressionActive) ?? false
        rateConfidence = try container.decodeIfPresent(Double.self, forKey: .rateConfidence) ?? 0
        depthConfidence = try container.decodeIfPresent(Double.self, forKey: .depthConfidence) ?? 0
    }
}

struct CPRPracticeSession: Identifiable, Codable, Equatable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let durationSeconds: Double

    let averageCPM: Double
    let bestCPM: Double
    let averageDepthCm: Double
    let depthConsistency: Double
    let handPlacementAccuracy: Double
    let elbowLockAccuracy: Double
    let recoilAccuracy: Double
    let handsOnTargetPercentage: Double
    let overallScore: Double

    let mainMistakeKey: String
    let improvementSuggestionKey: String

    let calibrationBaselineDepth: Double
    let calibrationBaselineAmplitude: Double
    let calibrationWasUsed: Bool

    var aiSummary: String?
    let frames: [CPRFrameMetric]

    var formattedStart: String {
        Self.dateTimeFormatter.string(from: startDate)
    }

    var formattedEnd: String {
        Self.dateTimeFormatter.string(from: endDate)
    }

    var formattedDuration: String {
        let minutes = Int(durationSeconds) / 60
        let seconds = Int(durationSeconds) % 60
        if minutes > 0 {
            return "\(minutes) min \(seconds) sec"
        }
        return "\(seconds) sec"
    }

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

struct CalibrationRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let baselineAmplitude: Double
    let baselineDepthCm: Double
    let cpmAtCalibration: Double
    let depthCmAtCalibration: Double
    let elbowAngleAtCalibration: Double
    let pressureScoreAtCalibration: Double

    var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

enum CPRSessionScoring {
    static func handPlacementScore(_ placement: HandPlacement) -> Double {
        switch placement {
        case .centered: return 1.0
        case .unknown: return 0.4
        default: return 0.2
        }
    }

    static func recoilScore(_ recoil: RecoilQuality) -> Double {
        switch recoil {
        case .full: return 1.0
        case .incomplete: return 0.25
        case .unknown: return 0.5
        }
    }

    static func calculateOverallScore(
        averageCPM: Double,
        averageDepth: Double,
        handAccuracy: Double,
        elbowAccuracy: Double,
        recoilAccuracy: Double,
        targetPercent: Double
    ) -> Double {
        let rateScore: Double
        if averageCPM >= CPRGuidelines.targetRateMin && averageCPM <= CPRGuidelines.targetRateMax {
            rateScore = 1.0
        } else if averageCPM > 0 {
            rateScore = max(0, 1.0 - abs(110 - averageCPM) / 60)
        } else {
            rateScore = 0.3
        }

        let depthScore: Double
        if averageDepth >= CPRGuidelines.targetDepthMinCm && averageDepth <= CPRGuidelines.targetDepthMaxCm {
            depthScore = 1.0
        } else if averageDepth > 0 {
            depthScore = max(0, 1.0 - abs(5.5 - averageDepth) / 3.0)
        } else {
            depthScore = 0.3
        }

        let score =
            rateScore * 0.25 +
            depthScore * 0.25 +
            handAccuracy * 0.20 +
            elbowAccuracy * 0.15 +
            recoilAccuracy * 0.10 +
            targetPercent * 0.05

        return min(max(score * 100, 0), 100)
    }

    static func mainMistakeKey(
        averageCPM: Double,
        averageDepth: Double,
        handAccuracy: Double,
        elbowAccuracy: Double,
        recoilAccuracy: Double,
        targetPercent: Double
    ) -> String {
        if targetPercent < 0.6 { return "move_hands_center" }
        if handAccuracy < 0.65 { return "move_hands_center" }
        if elbowAccuracy < 0.65 { return "straighten_arms" }
        if averageDepth > 0, averageDepth < CPRGuidelines.targetDepthMinCm { return "push_deeper" }
        if averageDepth > CPRGuidelines.targetDepthMaxCm { return "ease_depth" }
        if averageCPM > 0, averageCPM < CPRGuidelines.targetRateMin { return "push_faster" }
        if averageCPM > CPRGuidelines.targetRateMax { return "push_slower" }
        if recoilAccuracy < 0.65 { return "full_recoil" }
        return "good_form"
    }

    static func improvementSuggestionKey(for mistakeKey: String) -> String {
        switch mistakeKey {
        case "move_hands_center": return "progress_tip_hands"
        case "straighten_arms": return "progress_tip_elbows"
        case "push_deeper": return "progress_tip_depth"
        case "ease_depth": return "progress_tip_ease_depth"
        case "push_faster": return "progress_tip_rate_fast"
        case "push_slower": return "progress_tip_rate_slow"
        case "full_recoil": return "progress_tip_recoil"
        default: return "progress_tip_keep_going"
        }
    }

    /// Automated benchmark band for challenge demos.
    static func peerPercentile(for score: Double) -> Int {
        min(99, max(5, Int(score * 0.88 + 8)))
    }

    static func depthConsistency(_ frames: [CPRFrameMetric]) -> Double {
        let depths = frames.map(\.depthCm).filter { $0 > 0 }
        guard depths.count >= 3 else { return 0 }
        let mean = depths.reduce(0, +) / Double(depths.count)
        let variance = depths.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(depths.count)
        let stdDev = sqrt(variance)
        return max(0, 1.0 - stdDev / 2.5)
    }
}
