import Foundation
import CoreGraphics
import QuartzCore

/// Real-time CPR metric extraction using pose geometry + motion signal processing (on-device).
final class CPRMetricsEngine {
    private var wristHistory: [(time: TimeInterval, y: Double, amplitude: Double)] = []
    private var depthHistory: [Double] = []
    private let maxHistoryCount = 240
    private var calibration = CalibrationProfile.default
    private var lastPeakTime: TimeInterval?
    private var peakIntervals: [TimeInterval] = []
    private var lastPeakScanIndex: Int = 1

    func setCalibration(_ profile: CalibrationProfile) {
        calibration = profile
    }

    func reset() {
        wristHistory.removeAll()
        depthHistory.removeAll()
        peakIntervals.removeAll()
        lastPeakTime = nil
        lastPeakScanIndex = 1
    }

    func update(with joints: BodyJoints, lidarDepthCm: Double? = nil, patient: PatientDetection? = nil) -> CPRMetrics {
        let leftAngle = JointCPRCoachAnalyzer.elbowAngle(
            shoulder: joints.leftShoulder,
            elbow: joints.leftElbow,
            wrist: joints.leftWrist
        )
        let rightAngle = JointCPRCoachAnalyzer.elbowAngle(
            shoulder: joints.rightShoulder,
            elbow: joints.rightElbow,
            wrist: joints.rightWrist
        )
        let elbowAngle = (leftAngle + rightAngle) / 2.0

        let wristMid = midpoint(joints.leftWrist, joints.rightWrist)
        let shoulderMid = midpoint(joints.leftShoulder, joints.rightShoulder)
        let hipMid = hipMidpoint(from: joints)

        let now = CACurrentMediaTime()
        wristHistory.append((time: now, y: Double(wristMid.y), amplitude: 0))
        if wristHistory.count > maxHistoryCount {
            wristHistory.removeFirst()
        }

        let amplitude = recentStrokeAmplitude()
        let cpm = estimateCPM(now: now)
        let compressionActive = isCompressionActive(amplitude: amplitude, cpm: cpm)
        let rateConfidence = computeRateConfidence(
            cpm: cpm,
            amplitude: amplitude,
            peakCount: peakIntervals.count,
            historyFrames: wristHistory.count
        )
        let placement = JointCPRCoachAnalyzer.analyzeChestPlacement(
            joints: joints,
            patient: patient
        )
        let handsOnChest = placement.isAcceptable
        let handPlacement = handsOnChest ? HandPlacement.centered : placement.placement

        let depthCm = estimateDepth(
            amplitude: amplitude,
            lidarDepthCm: lidarDepthCm,
            shoulderMid: shoulderMid,
            wristMid: wristMid,
            neck: joints.neck
        )
        depthHistory.append(depthCm)
        if depthHistory.count > maxHistoryCount {
            depthHistory.removeFirst()
        }

        let smoothedDepth = smoothedDepthCm()
        let depthConfidence = computeDepthConfidence(
            amplitude: amplitude,
            sampleCount: depthHistory.count,
            compressionActive: compressionActive
        )

        let depthQuality = compressionActive && handsOnChest
            ? classifyDepth(smoothedDepth)
            : .unknown
        let recoil = compressionActive && handsOnChest ? classifyRecoil() : .unknown
        let pressureScore = computePressureScore(depthCm: smoothedDepth, amplitude: amplitude, cpm: cpm)
        let overall = classifyOverall(
            placement: handPlacement,
            elbowAngle: elbowAngle,
            cpm: cpm,
            depthQuality: depthQuality,
            recoil: recoil
        )

        return CPRMetrics(
            elbowAngle: elbowAngle,
            compressionsPerMinute: cpm,
            handPlacement: handPlacement,
            motionAmplitude: amplitude,
            estimatedDepthCm: smoothedDepth,
            depthQuality: depthQuality,
            recoilQuality: recoil,
            overallQuality: overall,
            confidence: joints.averageConfidence,
            pressureScore: pressureScore,
            compressionActive: compressionActive,
            rateConfidence: rateConfidence,
            depthConfidence: depthConfidence
        )
    }

    private func isCompressionActive(amplitude: Double, cpm: Double) -> Bool {
        guard amplitude >= 0.008, wristHistory.count >= 24 else { return false }
        return cpm >= 10 || peakIntervals.count >= 2
    }

    private func smoothedDepthCm() -> Double {
        guard !depthHistory.isEmpty else { return 0 }
        let recent = Array(depthHistory.suffix(min(16, depthHistory.count)))
        let sorted = recent.sorted()
        // Balanced percentile: peak depth without inflating like the 72nd did.
        let index = min(sorted.count - 1, Int(Double(sorted.count) * 0.58))
        return sorted[index]
    }

    private func computeRateConfidence(
        cpm: Double,
        amplitude: Double,
        peakCount: Int,
        historyFrames: Int
    ) -> Double {
        guard amplitude >= 0.007, historyFrames >= 30 else { return 0 }

        var score = 0.0
        if peakCount >= 2 { score += 0.35 }
        if peakCount >= 4 { score += 0.25 }
        if cpm >= 12, cpm <= 150 { score += 0.2 }
        if historyFrames >= 60 { score += 0.2 }
        return min(score, 1.0)
    }

    private func computeDepthConfidence(
        amplitude: Double,
        sampleCount: Int,
        compressionActive: Bool
    ) -> Double {
        guard compressionActive, sampleCount >= 12 else { return 0 }

        var score = 0.45
        if amplitude >= 0.010 { score += 0.30 }
        if sampleCount >= 30 { score += 0.25 }
        return min(score, 1.0)
    }

    // MARK: - Depth (camera amplitude + optional LiDAR fusion)

    private func estimateDepth(
        amplitude: Double,
        lidarDepthCm: Double?,
        shoulderMid: CGPoint,
        wristMid: CGPoint,
        neck: CGPoint?
    ) -> Double {
        let baseline = calibration.isCalibrated ? calibration.baselineAmplitude : 0.04
        let baselineDepth = calibration.isCalibrated
            ? calibration.baselineDepthCm
            : CPRGuidelines.targetDepthMinCm
        let scaleFactor = baselineDepth / max(baseline, 0.001)

        var cameraDepth = amplitude * scaleFactor

        if let neck {
            let neckScale = abs(neck.y - shoulderMid.y)
            if neckScale > 0.015 {
                let torsoDepth = amplitude / neckScale * CPRGuidelines.depthTorsoReferenceCm
                cameraDepth = cameraDepth * 0.62 + torsoDepth * 0.38
            }
        }

        cameraDepth = min(max(cameraDepth * CPRGuidelines.depthMeasurementScale, 0), 10)

        if let lidarDepthCm, lidarDepthCm > 0 {
            if cameraDepth > 0.5 {
                return min(lidarDepthCm * 0.72 + cameraDepth * 0.28, 10)
            }
            return min(lidarDepthCm, 10)
        }

        return cameraDepth
    }

    private func classifyDepth(_ depthCm: Double) -> DepthEstimate {
        guard depthCm > 0.5 else { return .unknown }
        if depthCm < CPRGuidelines.depthCoachBelowMinCm { return .tooShallow }
        if depthCm > CPRGuidelines.depthCoachAboveMaxCm { return .tooDeep }
        if depthCm >= CPRGuidelines.targetDepthMinCm,
           depthCm <= CPRGuidelines.targetDepthMaxCm {
            return .adequate
        }
        return .adequate
    }

    // MARK: - Rate (FFT + peak detection fusion)

    private func estimateCPM(now: TimeInterval) -> Double {
        guard wristHistory.count > 15 else { return 0 }

        updatePeakIntervals()

        let recentPeakCPM = peakIntervalCPM(recentOnly: true)
        let peakCPM = peakIntervalCPM(recentOnly: false)
        let zeroCrossCPM = estimateCPMFromVelocityZeroCrossings()
        let fftCPM = estimateCPMViaFFT()

        var weightedSum = 0.0
        var weightTotal = 0.0

        func contribute(_ value: Double, weight: Double) {
            guard value > 0 else { return }
            weightedSum += value * weight
            weightTotal += weight
        }

        // Balanced blend — no max-bias (that pushed "slow down" coaching).
        contribute(recentPeakCPM, weight: 0.38)
        contribute(zeroCrossCPM, weight: 0.22)
        contribute(fftCPM, weight: 0.30)
        contribute(peakCPM, weight: 0.10)

        if weightTotal > 0 {
            let blended = weightedSum / weightTotal
            return min(150, blended * CPRGuidelines.rateMeasurementScale)
        }

        return min(150, fallbackCPM() * CPRGuidelines.rateMeasurementScale)
    }

    private func peakIntervalCPM(recentOnly: Bool) -> Double {
        guard !peakIntervals.isEmpty else { return 0 }
        let intervals = recentOnly
            ? Array(peakIntervals.suffix(4))
            : peakIntervals
        let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
        return avgInterval > 0 ? 60.0 / avgInterval : 0
    }

    /// Count compression bottoms via velocity zero-crossings (responsive at high speed).
    private func estimateCPMFromVelocityZeroCrossings() -> Double {
        guard wristHistory.count >= 18 else { return 0 }

        let recent = Array(wristHistory.suffix(50))
        guard recent.count >= 18,
              let first = recent.first?.time,
              let last = recent.last?.time,
              last - first > 0.35 else { return 0 }

        var velocities: [Double] = []
        for i in 1..<recent.count {
            let dt = recent[i].time - recent[i - 1].time
            guard dt > 0 else { continue }
            velocities.append((recent[i].y - recent[i - 1].y) / dt)
        }

        guard velocities.count >= 6 else { return 0 }

        var crossings = 0
        for i in 1..<velocities.count {
            if velocities[i - 1] < 0 && velocities[i] >= 0 {
                crossings += 1
            }
        }

        return (Double(crossings) / (last - first)) * 60.0
    }

    /// Discrete Fourier analysis on wrist vertical displacement.
    private func estimateCPMViaFFT() -> Double {
        guard wristHistory.count >= 48 else { return 0 }

        let segment = Array(wristHistory.suffix(72))
        guard segment.count >= 48,
              let first = segment.first?.time,
              let last = segment.last?.time,
              last > first else { return 0 }

        let dt = (last - first) / Double(segment.count - 1)
        guard dt > 0 else { return 0 }

        var signal = segment.map(\.y)
        let mean = signal.reduce(0, +) / Double(signal.count)
        signal = signal.map { $0 - mean }

        var maxMag = 0.0
        var peakHz = 0.0

        var hz = 1.0
        while hz <= 3.0 {
            var real = 0.0
            var imag = 0.0
            for (index, sample) in signal.enumerated() {
                let angle = 2.0 * Double.pi * hz * Double(index) * dt
                real += sample * cos(angle)
                imag += sample * sin(angle)
            }
            let magnitude = sqrt(real * real + imag * imag)
            if magnitude > maxMag {
                maxMag = magnitude
                peakHz = hz
            }
            hz += 0.05
        }

        guard maxMag > 0.0004 else { return 0 }

        // Avoid locking onto half-frequency when compressing fast.
        let doubleHz = peakHz * 2.0
        if doubleHz <= 3.0 {
            var real = 0.0
            var imag = 0.0
            for (index, sample) in signal.enumerated() {
                let angle = 2.0 * Double.pi * doubleHz * Double(index) * dt
                real += sample * cos(angle)
                imag += sample * sin(angle)
            }
            let doubleMag = sqrt(real * real + imag * imag)
            if doubleMag > maxMag * 0.64 {
                peakHz = doubleHz
            }
        }

        return peakHz * 60.0
    }

    private func updatePeakIntervals() {
        guard wristHistory.count > 2 else { return }

        let ys = wristHistory.map(\.y)
        let start = max(1, lastPeakScanIndex)
        let end = wristHistory.count - 1
        guard start < end else { return }

        let extremaEpsilon = 0.00015
        let minInterval = 0.16

        for i in start..<end {
            let prev = ys[i - 1]
            let curr = ys[i]
            let next = ys[i + 1]

            let isMin = curr + extremaEpsilon <= prev && curr + extremaEpsilon <= next
            guard isMin else { continue }

            let t = wristHistory[i].time
            if let last = lastPeakTime {
                let interval = t - last
                if interval >= minInterval {
                    peakIntervals.append(interval)
                    if peakIntervals.count > 10 {
                        peakIntervals.removeFirst()
                    }
                }
            }
            lastPeakTime = t
        }

        lastPeakScanIndex = max(1, wristHistory.count - 2)
    }

    private func fallbackCPM() -> Double {
        guard wristHistory.count > 20 else { return 0 }
        var minimaCount = 0
        let ys = wristHistory.map(\.y)

        for i in 1..<(ys.count - 1) {
            if ys[i] < ys[i - 1] && ys[i] < ys[i + 1] {
                minimaCount += 1
            }
        }

        guard let first = wristHistory.first?.time,
              let last = wristHistory.last?.time,
              last > first else { return 0 }

        return (Double(minimaCount) / (last - first)) * 60.0
    }

    private func recentStrokeAmplitude() -> Double {
        guard wristHistory.count >= 12 else { return estimateAmplitude() }

        let recent = wristHistory.suffix(40)
        let ys = recent.map(\.y)
        guard let minY = ys.min(), let maxY = ys.max() else { return 0 }
        return maxY - minY
    }

    private func estimateAmplitude() -> Double {
        let ys = wristHistory.map(\.y)
        guard let minY = ys.min(), let maxY = ys.max() else { return 0 }
        return maxY - minY
    }

    private func classifyRecoil() -> RecoilQuality {
        guard wristHistory.count > 30 else { return .unknown }
        let ys = wristHistory.suffix(30).map(\.y)
        guard let minY = ys.min(), let maxY = ys.max() else { return .unknown }
        let range = maxY - minY
        guard range > 0.005 else { return .unknown }

        let recentMax = ys.max() ?? maxY
        let recentMin = ys.min() ?? minY
        let recoilRatio = (recentMax - recentMin) / range

        return recoilRatio >= CPRGuidelines.minRecoilRatio ? .full : .incomplete
    }

    private func computePressureScore(depthCm: Double, amplitude: Double, cpm: Double) -> Double {
        var score = 0.0

        if depthCm >= CPRGuidelines.targetDepthMinCm && depthCm <= CPRGuidelines.targetDepthMaxCm {
            score += 40
        } else if depthCm > 0 {
            let deviation = min(abs(depthCm - 5.5), 3.0)
            score += max(0, 40 - deviation * 10)
        }

        if cpm >= CPRGuidelines.targetRateMin && cpm <= CPRGuidelines.targetRateMax {
            score += 35
        } else if cpm > 0 {
            let deviation = min(abs(cpm - 110), 40)
            score += max(0, 35 - deviation * 0.8)
        }

        score += min(amplitude * 500, 25)
        return min(score, 100)
    }

    private func classifyOverall(
        placement: HandPlacement,
        elbowAngle: Double,
        cpm: Double,
        depthQuality: DepthEstimate,
        recoil: RecoilQuality
    ) -> CompressionQuality {
        var points = 0

        if placement == .centered { points += 2 }
        if elbowAngle >= CPRGuidelines.targetElbowAngleMin { points += 2 }
        if cpm >= CPRGuidelines.targetRateMin && cpm <= CPRGuidelines.targetRateMax { points += 2 }
        if depthQuality == .adequate { points += 2 }
        if recoil == .full { points += 1 }

        switch points {
        case 8...: return .excellent
        case 6...7: return .good
        case 3...5: return .needsWork
        case 1...2: return .poor
        default: return .unknown
        }
    }

    private func hipMidpoint(from joints: BodyJoints) -> CGPoint? {
        switch (joints.leftHip, joints.rightHip) {
        case let (.some(l), .some(r)):
            return midpoint(l, r)
        case let (.some(l), .none):
            return l
        case let (.none, .some(r)):
            return r
        default:
            return nil
        }
    }

    private func midpoint(_ p1: CGPoint, _ p2: CGPoint) -> CGPoint {
        CGPoint(x: (p1.x + p2.x) / 2.0, y: (p1.y + p2.y) / 2.0)
    }

}
