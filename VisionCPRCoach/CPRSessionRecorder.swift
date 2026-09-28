import Foundation

@MainActor
final class CPRSessionRecorder: ObservableObject {
    @Published private(set) var currentFrames: [CPRFrameMetric] = []

    private var startDate: Date?
    private var sessionStartTime: TimeInterval = 0
    private var lastSampleTime: TimeInterval = 0
    private let sampleInterval: TimeInterval = 0.45

    var isRecording: Bool { startDate != nil }

    func start() {
        currentFrames = []
        startDate = Date()
        sessionStartTime = Date().timeIntervalSince1970
        lastSampleTime = 0
    }

    func record(metrics: CPRMetrics, handsOnTarget: Bool) {
        guard startDate != nil else { return }

        let now = Date().timeIntervalSince1970
        guard now - lastSampleTime >= sampleInterval else { return }
        lastSampleTime = now

        let timestamp = now - sessionStartTime
        let frame = CPRFrameMetric(
            id: UUID(),
            timestamp: timestamp,
            cpm: metrics.compressionsPerMinute,
            depthCm: metrics.estimatedDepthCm,
            elbowAngle: metrics.elbowAngle,
            handPlacementScore: CPRSessionScoring.handPlacementScore(metrics.handPlacement),
            recoilScore: CPRSessionScoring.recoilScore(metrics.recoilQuality),
            handsOnTarget: handsOnTarget,
            pressureScore: metrics.pressureScore,
            handPlacement: metrics.handPlacement.rawValue,
            motionAmplitude: metrics.motionAmplitude,
            depthQuality: metrics.depthQuality.rawValue,
            recoilQuality: metrics.recoilQuality.rawValue,
            overallQuality: metrics.overallQuality.rawValue,
            confidence: metrics.confidence,
            compressionActive: metrics.compressionActive,
            rateConfidence: metrics.rateConfidence,
            depthConfidence: metrics.depthConfidence
        )
        currentFrames.append(frame)
    }

    func finish(calibration: CalibrationProfile) -> CPRPracticeSession? {
        guard let startDate else { return nil }
        let endDate = Date()
        let duration = endDate.timeIntervalSince(startDate)

        defer {
            self.startDate = nil
            currentFrames = []
        }

        guard duration >= 5, !currentFrames.isEmpty else { return nil }

        let avgCPM = average(currentFrames.map(\.cpm).filter { $0 >= 10 })
        let bestCPM = currentFrames.map(\.cpm).filter { $0 >= 10 }.max() ?? 0
        let avgDepth = average(currentFrames.map(\.depthCm).filter { $0 > 0 })
        let handAccuracy = average(currentFrames.map(\.handPlacementScore))
        let elbowAccuracy = elbowLockAccuracy(currentFrames)
        let recoilAccuracy = average(currentFrames.map(\.recoilScore))
        let targetPercent = Double(currentFrames.filter(\.handsOnTarget).count) / Double(currentFrames.count)
        let depthConsistency = CPRSessionScoring.depthConsistency(currentFrames)

        let mistake = CPRSessionScoring.mainMistakeKey(
            averageCPM: avgCPM,
            averageDepth: avgDepth,
            handAccuracy: handAccuracy,
            elbowAccuracy: elbowAccuracy,
            recoilAccuracy: recoilAccuracy,
            targetPercent: targetPercent
        )

        let score = CPRSessionScoring.calculateOverallScore(
            averageCPM: avgCPM,
            averageDepth: avgDepth,
            handAccuracy: handAccuracy,
            elbowAccuracy: elbowAccuracy,
            recoilAccuracy: recoilAccuracy,
            targetPercent: targetPercent
        )

        return CPRPracticeSession(
            id: UUID(),
            startDate: startDate,
            endDate: endDate,
            durationSeconds: duration,
            averageCPM: avgCPM,
            bestCPM: bestCPM,
            averageDepthCm: avgDepth,
            depthConsistency: depthConsistency,
            handPlacementAccuracy: handAccuracy,
            elbowLockAccuracy: elbowAccuracy,
            recoilAccuracy: recoilAccuracy,
            handsOnTargetPercentage: targetPercent,
            overallScore: score,
            mainMistakeKey: mistake,
            improvementSuggestionKey: CPRSessionScoring.improvementSuggestionKey(for: mistake),
            calibrationBaselineDepth: calibration.baselineDepthCm,
            calibrationBaselineAmplitude: calibration.baselineAmplitude,
            calibrationWasUsed: calibration.isCalibrated,
            aiSummary: nil,
            frames: currentFrames
        )
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func elbowLockAccuracy(_ frames: [CPRFrameMetric]) -> Double {
        guard !frames.isEmpty else { return 0 }
        let good = frames.filter { $0.elbowAngle >= CPRGuidelines.setupElbowAngleMin }.count
        return Double(good) / Double(frames.count)
    }
}
