import Foundation
import CoreGraphics

/// On-device CPR error-action recognizer (CPR-Coach 14-class taxonomy).
///
/// Adaptive: every class is scored only when the joints/hands it needs are visible, so a close-up
/// arm view still yields hand/arm/rate/depth classes while a full-body side view unlocks
/// Squatting / Standing / Jump Pressing. Each firing class gets a confidence in [0,1], and the
/// headline class is gated by the composite confidence score `CS = objectness × temporal_consistency`
/// to suppress single-frame false positives.
final class CPRActionRecognitionEngine {

    // MARK: - Temporal state

    private var wristX: [Double] = []
    private var wristY: [Double] = []
    private var hipY: [Double] = []
    private var classHistory: [CPRErrorAction] = []

    private let motionWindow = 48          // ~1.5 s at 30 fps
    private let classWindow = 9            // frames used for temporal consistency
    private let minFireConfidence = 0.45   // a class must exceed this to be "active"
    private let csGate = 0.30              // below this CS, an error is demoted toward Correct

    func reset() {
        wristX.removeAll()
        wristY.removeAll()
        hipY.removeAll()
        classHistory.removeAll()
    }

    // MARK: - Main entry

    func recognize(scene: CPRSceneAnalysis, metrics: CPRMetrics, joints: BodyJoints) -> ActionRecognitionResult {
        let shoulderMid = mid(joints.leftShoulder, joints.rightShoulder)
        let wristMid = mid(joints.leftWrist, joints.rightWrist)

        pushMotion(wristMid: wristMid, rescuer: scene.rescuer)

        var scores: [CPRErrorAction: Double] = [:]

        // --- Hand-shape classes (need detected hands) ---
        if let s = scoreSingleHand(hands: scene.handPoses, joints: joints) { scores[.singleHand] = s }
        if let s = scoreOverlapHands(hands: scene.handPoses) { scores[.overlapHands] = s }
        if let s = scoreClenchingHands(hands: scene.handPoses) { scores[.clenchingHands] = s }

        // --- Arm-geometry classes (need arm joints) ---
        if let s = scoreBendingArms(metrics: metrics) { scores[.bendingArms] = s }
        if let s = scoreTiltingArms(shoulderMid: shoulderMid, wristMid: wristMid) { scores[.tiltingArms] = s }

        // --- Whole-body posture classes (need lower body — side view) ---
        if let rescuer = scene.rescuer {
            if let s = scoreStanding(rescuer) { scores[.standing] = s }
            if let s = scoreSquatting(rescuer) { scores[.squatting] = s }
            if let s = scoreJumpPressing(rescuer: rescuer, metrics: metrics) { scores[.jumpPressing] = s }
        }

        // --- Technique classes (metrics + temporal) ---
        if let s = scoreWrongPosition(metrics: metrics) { scores[.wrongPosition] = s }
        if let s = scoreInsufficient(metrics: metrics) { scores[.insufficientPressing] = s }
        if let s = scoreExcessive(metrics: metrics) { scores[.excessivePressing] = s }
        if let s = scoreSlowFrequency(metrics: metrics) { scores[.slowFrequency] = s }
        if let s = scoreRandomPosition() { scores[.randomPositionPressing] = s }

        // --- Pick the headline class (severity-weighted) ---
        let active = scores
            .filter { $0.value >= minFireConfidence }
            .sorted { lhs, rhs in
                let a = Double(lhs.key.severity) * lhs.value
                let b = Double(rhs.key.severity) * rhs.value
                return a > b
            }

        let rawPrimary = active.first?.key ?? .correct
        let rawConfidence = active.first?.value ?? correctConfidence(metrics: metrics)

        // --- Composite confidence gating ---
        classHistory.append(rawPrimary)
        if classHistory.count > classWindow { classHistory.removeFirst() }

        let objectness = clamp(max(scene.rescuerConfidence, joints.averageConfidence))
        let temporalConsistency = classHistory.isEmpty
            ? 0
            : Double(classHistory.filter { $0 == rawPrimary }.count) / Double(classHistory.count)
        let cs = objectness * temporalConsistency

        var primary = rawPrimary
        var displayConfidence = rawConfidence * (0.45 + 0.55 * cs)

        // Suppress unstable single-frame error spikes (false-positive elimination).
        if primary.isError && cs < csGate {
            primary = .correct
            displayConfidence = correctConfidence(metrics: metrics) * (0.45 + 0.55 * objectness)
        }

        let activeErrors = active.map(\.key).filter { $0.isError }

        return ActionRecognitionResult(
            primary: primary,
            confidence: clamp(displayConfidence),
            scores: scores,
            objectness: objectness,
            temporalConsistency: temporalConsistency,
            activeErrors: activeErrors
        )
    }

    // MARK: - Motion history

    private func pushMotion(wristMid: CGPoint, rescuer: FullBodySkeleton?) {
        append(&wristX, Double(wristMid.x))
        append(&wristY, Double(wristMid.y))

        if let lh = rescuer?.leftHip, let rh = rescuer?.rightHip {
            append(&hipY, Double((lh.y + rh.y) / 2))
        } else if let root = rescuer?.root {
            append(&hipY, Double(root.y))
        }
    }

    private func append(_ buffer: inout [Double], _ value: Double) {
        buffer.append(value)
        if buffer.count > motionWindow { buffer.removeFirst() }
    }

    // MARK: - Hand-shape detectors

    private func scoreSingleHand(hands: [HandPose], joints: BodyJoints) -> Double? {
        // Need either a hand detection or both wrists to reason about hand count.
        let wristDist = dist(joints.leftWrist, joints.rightWrist)

        // Two well-detected, clearly separated hands → one-handed / hands apart.
        if hands.count >= 2 {
            let separation = dist(hands[0].wrist, hands[1].wrist)
            if separation > 0.14 {
                return clamp((separation - 0.12) / 0.18)
            }
            return nil
        }

        // Exactly one hand detected while wrists sit apart → likely single-handed compressions.
        if hands.count == 1 {
            let base = 0.55
            let boost = wristDist > 0.14 ? clamp((wristDist - 0.12) / 0.2) * 0.4 : 0
            return clamp(base + boost)
        }

        // No hand detected: fall back to wrist separation only (weaker evidence).
        if wristDist > 0.18 {
            return clamp((wristDist - 0.16) / 0.2) * 0.7
        }
        return nil
    }

    private func scoreOverlapHands(hands: [HandPose]) -> Double? {
        guard hands.count >= 2 else { return nil }
        let iou = boxIoU(hands[0].boundingBox, hands[1].boundingBox)
        guard iou > 0.35 else { return nil }

        // Proper stacking = vertical offset (one hand on the back of the other). Lateral offset with
        // high overlap suggests crossed / side-by-side overlapping hands (the error case).
        let dx = abs(hands[0].boundingBox.midX - hands[1].boundingBox.midX)
        let dy = abs(hands[0].boundingBox.midY - hands[1].boundingBox.midY)
        guard dx > dy else { return nil }

        return clamp((iou - 0.3) / 0.5)
    }

    private func scoreClenchingHands(hands: [HandPose]) -> Double? {
        let withFingers = hands.filter { !$0.fingertips.isEmpty }
        guard !withFingers.isEmpty else { return nil }
        let minExtension = withFingers.map(\.fingerExtension).min() ?? 1
        // Flat heel-of-palm keeps fingers extended (~1.1+). A fist curls them in (< ~0.9).
        guard minExtension < 0.92 else { return nil }
        return clamp((0.92 - minExtension) / 0.45)
    }

    // MARK: - Arm-geometry detectors

    private func scoreBendingArms(metrics: CPRMetrics) -> Double? {
        let angle = metrics.elbowAngle
        guard angle > 1 else { return nil }
        guard angle < CPRGuidelines.targetElbowAngleMin else { return nil }
        return clamp((CPRGuidelines.targetElbowAngleMin - angle) / 40)
    }

    private func scoreTiltingArms(shoulderMid: CGPoint, wristMid: CGPoint) -> Double? {
        let dx = abs(Double(wristMid.x - shoulderMid.x))
        let dy = Double(shoulderMid.y - wristMid.y)   // >0 when shoulders are above the wrists
        guard dy > 0.04 else { return nil }            // need a real "leaning over" geometry
        let tiltDeg = atan2(dx, dy) * 180 / .pi
        guard tiltDeg > 20 else { return nil }
        return clamp((tiltDeg - 18) / 32)
    }

    // MARK: - Whole-body posture detectors

    private func scoreStanding(_ s: FullBodySkeleton) -> Double? {
        guard let hip = midOpt(s.leftHip, s.rightHip),
              let knee = midOpt(s.leftKnee, s.rightKnee),
              let ankle = midOpt(s.leftAnkle, s.rightAnkle) else { return nil }

        let kneeAngle = angle(hip, knee, ankle)            // ~180 when legs straight
        let verticalSpan = Double(hip.y - ankle.y)         // tall stack = upright
        guard kneeAngle > 150, verticalSpan > 0.32 else { return nil }

        let straightness = clamp((kneeAngle - 150) / 30)
        let upright = clamp((verticalSpan - 0.3) / 0.25)
        return clamp(straightness * 0.6 + upright * 0.4)
    }

    private func scoreSquatting(_ s: FullBodySkeleton) -> Double? {
        guard let hip = midOpt(s.leftHip, s.rightHip),
              let knee = midOpt(s.leftKnee, s.rightKnee),
              let ankle = midOpt(s.leftAnkle, s.rightAnkle) else { return nil }

        let kneeAngle = angle(hip, knee, ankle)
        guard kneeAngle < 120 else { return nil }          // deeply bent knees

        // Squat (vs kneel): shank stays fairly vertical (ankle roughly under knee).
        let shankHorizontal = abs(Double(knee.x - ankle.x))
        let shankVertical = abs(Double(knee.y - ankle.y))
        guard shankVertical > shankHorizontal else { return nil }
        // Hips elevated well above ankles (not resting on the floor like a kneel).
        guard Double(hip.y - ankle.y) > 0.18 else { return nil }

        return clamp((120 - kneeAngle) / 60)
    }

    private func scoreJumpPressing(rescuer: FullBodySkeleton, metrics: CPRMetrics) -> Double? {
        guard hipY.count >= 20 else { return nil }
        let recentHip = Array(hipY.suffix(30))
        let hipAmp = (recentHip.max() ?? 0) - (recentHip.min() ?? 0)
        guard hipAmp > 0.035 else { return nil }

        // Whole-body bob: hips move on the same order as the wrists instead of arms doing the work.
        let recentWrist = Array(wristY.suffix(30))
        let wristAmp = (recentWrist.max() ?? 0) - (recentWrist.min() ?? 0)
        guard hipAmp > wristAmp * 0.45 else { return nil }

        return clamp((hipAmp - 0.03) / 0.07)
    }

    // MARK: - Technique detectors

    private func scoreWrongPosition(metrics: CPRMetrics) -> Double? {
        switch metrics.handPlacement {
        case .tooFarLeft, .tooFarRight, .tooHigh, .tooLow:
            return 0.9
        case .centered, .unknown:
            return nil
        }
    }

    private func scoreInsufficient(metrics: CPRMetrics) -> Double? {
        guard metrics.depthQuality == .tooShallow else { return nil }
        let deficit = max(CPRGuidelines.targetDepthMinCm - metrics.estimatedDepthCm, 0)
        return clamp(0.6 + deficit / 5)
    }

    private func scoreExcessive(metrics: CPRMetrics) -> Double? {
        guard metrics.depthQuality == .tooDeep else { return nil }
        let excess = max(metrics.estimatedDepthCm - CPRGuidelines.targetDepthMaxCm, 0)
        return clamp(0.6 + excess / 4)
    }

    private func scoreSlowFrequency(metrics: CPRMetrics) -> Double? {
        let cpm = metrics.compressionsPerMinute
        guard cpm > 1, cpm < CPRGuidelines.targetRateMin else { return nil }
        return clamp((CPRGuidelines.targetRateMin - cpm) / 45)
    }

    private func scoreRandomPosition() -> Double? {
        guard wristX.count >= 24 else { return nil }
        let recent = Array(wristX.suffix(40))
        let range = (recent.max() ?? 0) - (recent.min() ?? 0)
        guard range > 0.07 else { return nil }   // hands wandering laterally frame to frame
        return clamp((range - 0.06) / 0.12)
    }

    // MARK: - Correct confidence

    private func correctConfidence(metrics: CPRMetrics) -> Double {
        var score = 0.4
        if metrics.handPlacement == .centered { score += 0.2 }
        if metrics.elbowAngle >= CPRGuidelines.targetElbowAngleMin { score += 0.15 }
        if metrics.depthQuality == .adequate { score += 0.15 }
        let cpm = metrics.compressionsPerMinute
        if cpm >= CPRGuidelines.targetRateMin && cpm <= CPRGuidelines.targetRateMax { score += 0.1 }
        return clamp(score)
    }

    // MARK: - Geometry helpers

    private func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }

    private func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    private func midOpt(_ a: CGPoint?, _ b: CGPoint?) -> CGPoint? {
        switch (a, b) {
        case let (.some(l), .some(r)): return mid(l, r)
        case let (.some(l), .none): return l
        case let (.none, .some(r)): return r
        default: return nil
        }
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(Double(a.x - b.x), Double(a.y - b.y))
    }

    private func angle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
        let ba = CGVector(dx: a.x - b.x, dy: a.y - b.y)
        let bc = CGVector(dx: c.x - b.x, dy: c.y - b.y)
        let dot = ba.dx * bc.dx + ba.dy * bc.dy
        let magBA = hypot(ba.dx, ba.dy)
        let magBC = hypot(bc.dx, bc.dy)
        guard magBA > 0, magBC > 0 else { return 0 }
        let cosTheta = max(-1.0, min(1.0, Double(dot / (magBA * magBC))))
        return acos(cosTheta) * 180 / .pi
    }

    private func boxIoU(_ a: CGRect, _ b: CGRect) -> Double {
        let inter = a.intersection(b)
        guard !inter.isNull, inter.width > 0, inter.height > 0 else { return 0 }
        let interArea = Double(inter.width * inter.height)
        let union = Double(a.width * a.height + b.width * b.height) - interArea
        guard union > 0 else { return 0 }
        return interArea / union
    }
}
