import Foundation
import Vision
import CoreMedia
import CoreVideo
import CoreGraphics
import QuartzCore

/// Single full-frame MoveNet pass + Vision human rects / hands for CPR scene logic.
final class MultiPersonPoseAnalyzer {
    private let moveNet = MoveNetPoseEstimator.shared

    /// Vision body pose — fallback only when MoveNet is unavailable or fails.
    private let poseRequest: VNDetectHumanBodyPoseRequest = {
        let request = VNDetectHumanBodyPoseRequest()
        // Use the newest pose model the OS supports (more accurate than pinning revision 1).
        if let latest = VNDetectHumanBodyPoseRequest.supportedRevisions.max() {
            request.revision = latest
        }
        return request
    }()

    private let humanRectRequest = VNDetectHumanRectanglesRequest()

    private let handRequest: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        return request
    }()

    private let tracker = PoseTrackingFilter()

    func resetTracking() {
        tracker.reset()
        moveNet.resetCrop()
    }

    func processFrame(
        _ sampleBuffer: CMSampleBuffer,
        completion: @escaping (CPRSceneAnalysis) -> Void
    ) {
        guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else {
            completion(emptyScene())
            return
        }

        var skeletons: [FullBodySkeleton] = []
        var moveNetUsed = false
        var livePose: MoveNetPose?

        let moveNetPrimary = moveNet.isModelLoaded

        if moveNetPrimary, let pose = try? moveNet.estimatePose(from: sampleBuffer) {
            livePose = pose
            let skeleton = pose.toFullBodySkeleton()
            if skeleton.leftShoulder != nil || skeleton.rightShoulder != nil {
                skeletons.append(skeleton)
                moveNetUsed = true
            }
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            completion(emptyScene())
            return
        }

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .right,
            options: [:]
        )

        do {
            if skeletons.isEmpty, !moveNetPrimary {
                try handler.perform([poseRequest, humanRectRequest, handRequest])
                skeletons = (poseRequest.results ?? []).compactMap { extractSkeleton(from: $0) }
            } else {
                try handler.perform([humanRectRequest, handRequest])
            }

            let humanRects = humanRectRequest.results ?? []
            let handObservations = handRequest.results ?? []

            let associations = associateSkeletonsWithRects(skeletons: skeletons, rects: humanRects)

            let (rawRescuer, fallbackPatient) = classifyScene(
                skeletons: skeletons,
                associations: associations,
                humanRects: humanRects
            )

            // Patient gating + sticky lock live in PoseTrackingFilter.
            let rawPatient = fallbackPatient

            // Objectness for the rescuer: matched person-rectangle confidence if available.
            let rawRescuerRectConfidence = associations
                .first { $0.skeleton == rawRescuer }
                .map(\.rectConfidence) ?? 0

            let timestamp = CACurrentMediaTime()
            let (rescuer, patient) = tracker.process(
                rawRescuer: rawRescuer,
                rawPatient: rawPatient,
                timestamp: timestamp
            )

            let hands = extractHands(handObservations, rescuer: rescuer)
            let displayRescuer = (rescuer ?? rawRescuer ?? skeletons.first)
                .map { moveNetUsed ? $0 : refineSkeletonWithHands($0, hands: hands) }
                ?? rescuer
                ?? rawRescuer
                ?? skeletons.first

            let quality = computeQuality(
                rescuer: displayRescuer,
                patient: patient,
                skeletonCount: skeletons.count,
                moveNetActive: moveNetUsed
            )

            let (rescuerBox, rescuerConfidence) = rescuerBoxAndConfidence(
                rescuer: displayRescuer,
                rectConfidence: rawRescuerRectConfidence
            )

            completion(CPRSceneAnalysis(
                rescuer: displayRescuer,
                patient: patient,
                rescuerBox: rescuerBox,
                rescuerConfidence: rescuerConfidence,
                handPoses: hands,
                personCount: max(skeletons.count, humanRects.count),
                detectionQuality: quality,
                moveNetPose: livePose,
                patientMoveNetPose: nil,
                patientCPRTarget: nil,
                timestamp: timestamp
            ))
        } catch {
            print("MultiPersonPoseAnalyzer error: \(error)")
            completion(emptyScene())
        }
    }

    /// Portrait-up pixel buffer (LiDAR / ARKit camera pipeline).
    func processPortraitBuffer(
        _ pixelBuffer: CVPixelBuffer,
        completion: @escaping (CPRSceneAnalysis) -> Void
    ) {
        var skeletons: [FullBodySkeleton] = []
        var moveNetUsed = false
        var livePose: MoveNetPose?

        let moveNetPrimary = moveNet.isModelLoaded

        if moveNetPrimary, let pose = try? moveNet.estimatePose(fromPortrait: pixelBuffer) {
            livePose = pose
            let skeleton = pose.toFullBodySkeleton()
            if skeleton.leftShoulder != nil || skeleton.rightShoulder != nil {
                skeletons.append(skeleton)
                moveNetUsed = true
            }
        }

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )

        do {
            if skeletons.isEmpty, !moveNetPrimary {
                try handler.perform([poseRequest, humanRectRequest, handRequest])
                skeletons = (poseRequest.results ?? []).compactMap { extractSkeleton(from: $0) }
            } else {
                try handler.perform([humanRectRequest, handRequest])
            }

            let humanRects = humanRectRequest.results ?? []
            let handObservations = handRequest.results ?? []

            let associations = associateSkeletonsWithRects(skeletons: skeletons, rects: humanRects)

            let (rawRescuer, fallbackPatient) = classifyScene(
                skeletons: skeletons,
                associations: associations,
                humanRects: humanRects
            )

            let rawPatient = fallbackPatient

            let rawRescuerRectConfidence = associations
                .first { $0.skeleton == rawRescuer }
                .map(\.rectConfidence) ?? 0

            let timestamp = CACurrentMediaTime()
            let (rescuer, patient) = tracker.process(
                rawRescuer: rawRescuer,
                rawPatient: rawPatient,
                timestamp: timestamp
            )

            let hands = extractHands(handObservations, rescuer: rescuer)
            let displayRescuer = (rescuer ?? rawRescuer ?? skeletons.first)
                .map { moveNetUsed ? $0 : refineSkeletonWithHands($0, hands: hands) }
                ?? rescuer
                ?? rawRescuer
                ?? skeletons.first

            let quality = computeQuality(
                rescuer: displayRescuer,
                patient: patient,
                skeletonCount: skeletons.count,
                moveNetActive: moveNetUsed
            )

            let (rescuerBox, rescuerConfidence) = rescuerBoxAndConfidence(
                rescuer: displayRescuer,
                rectConfidence: rawRescuerRectConfidence
            )

            completion(CPRSceneAnalysis(
                rescuer: displayRescuer,
                patient: patient,
                rescuerBox: rescuerBox,
                rescuerConfidence: rescuerConfidence,
                handPoses: hands,
                personCount: max(skeletons.count, humanRects.count),
                detectionQuality: quality,
                moveNetPose: livePose,
                patientMoveNetPose: nil,
                patientCPRTarget: nil,
                timestamp: timestamp
            ))
        } catch {
            print("MultiPersonPoseAnalyzer AR error: \(error)")
            completion(emptyScene())
        }
    }

    // MARK: - Skeleton extraction

    private func extractSkeleton(from observation: VNHumanBodyPoseObservation) -> FullBodySkeleton? {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }

        func pt(_ joint: VNHumanBodyPoseObservation.JointName, _ minConf: Float) -> CGPoint? {
            guard let p = points[joint], p.confidence >= minConf else { return nil }
            return CGPoint(x: p.location.x, y: p.location.y)
        }

        // Lower thresholds keep more joints alive; the 1€ filter + per-joint hold remove the jitter.
        let core: Float = 0.15   // shoulders / neck / hips / root
        let limb: Float = 0.10   // elbows / wrists / knees
        let ext: Float = 0.08    // ankles / nose

        // Confidence from the present key joints (not the whole noisy point cloud).
        let keyJoints: [VNHumanBodyPoseObservation.JointName] = [
            .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
            .leftWrist, .rightWrist, .leftHip, .rightHip
        ]
        let keyConfs = keyJoints
            .compactMap { points[$0]?.confidence }
            .map(Double.init)
            .filter { $0 > 0.05 }
        let avgConf = keyConfs.isEmpty
            ? Double(observation.confidence)
            : keyConfs.reduce(0, +) / Double(keyConfs.count)

        let skeleton = FullBodySkeleton(
            nose: pt(.nose, ext),
            neck: pt(.neck, core),
            leftShoulder: pt(.leftShoulder, core),
            rightShoulder: pt(.rightShoulder, core),
            leftElbow: pt(.leftElbow, limb),
            rightElbow: pt(.rightElbow, limb),
            leftWrist: pt(.leftWrist, limb),
            rightWrist: pt(.rightWrist, limb),
            leftHip: pt(.leftHip, core),
            rightHip: pt(.rightHip, core),
            leftKnee: pt(.leftKnee, limb),
            rightKnee: pt(.rightKnee, limb),
            leftAnkle: pt(.leftAnkle, ext),
            rightAnkle: pt(.rightAnkle, ext),
            root: pt(.root, core),
            averageConfidence: avgConf
        )

        // Accept any viable upper body — at least one shoulder and five tracked joints — instead of
        // demanding both wrists (which are often hidden behind the chest from the side).
        let hasShoulder = skeleton.leftShoulder != nil || skeleton.rightShoulder != nil
        guard hasShoulder, skeleton.allPoints.count >= 5 else { return nil }
        return skeleton
    }

    // MARK: - Pose ↔ rectangle association

    private struct SkeletonAssociation {
        let skeleton: FullBodySkeleton
        let rect: CGRect?
        let rectConfidence: Double
    }

    private func associateSkeletonsWithRects(
        skeletons: [FullBodySkeleton],
        rects: [VNHumanObservation]
    ) -> [SkeletonAssociation] {
        skeletons.map { skeleton in
            let center = skeleton.centerPoint ?? skeleton.leftWrist ?? skeleton.rightWrist ?? .zero
            let match = rects.max { a, b in
                overlapScore(center: center, rect: a.boundingBox) < overlapScore(center: center, rect: b.boundingBox)
            }
            if let match {
                return SkeletonAssociation(
                    skeleton: skeleton,
                    rect: match.boundingBox,
                    rectConfidence: Double(match.confidence)
                )
            }
            return SkeletonAssociation(skeleton: skeleton, rect: nil, rectConfidence: 0)
        }
    }

    private func overlapScore(center: CGPoint, rect: CGRect) -> Double {
        if rect.contains(center) { return 1.0 }
        let dx = max(max(rect.minX - center.x, center.x - rect.maxX), 0)
        let dy = max(max(rect.minY - center.y, center.y - rect.maxY), 0)
        return max(0, 1.0 - hypot(dx, dy) * 4)
    }

    // MARK: - Rescuer vs patient

    private func classifyScene(
        skeletons: [FullBodySkeleton],
        associations: [SkeletonAssociation],
        humanRects: [VNHumanObservation]
    ) -> (rescuer: FullBodySkeleton?, patient: PatientDetection?) {
        guard !skeletons.isEmpty else {
            return (nil, nil)
        }

        let scored = associations.map { assoc -> (SkeletonAssociation, Double, Double, Double) in
            (assoc, scoreAsRescuer(assoc.skeleton), scoreAsPatientSkeleton(assoc.skeleton), centralityScore(assoc.skeleton))
        }

        if skeletons.count == 1 {
            let rescuer = skeletons[0]

            if let patientRect = bestHorizontalPatientRect(from: humanRects, excluding: rescuer) {
                return (rescuer, patientFromTorsoRect(
                    patientRect,
                    confidence: Double(patientRect.confidence),
                    rescuer: rescuer
                ))
            }

            if let inferred = CPRChestTargetEstimator.chestTargetUnderHandsIfCPRPosture(rescuer: rescuer) {
                return (rescuer, inferred)
            }

            return (rescuer, nil)
        }

        let rescuer = scored.max { a, b in
            (a.1 + a.3) < (b.1 + b.3)
        }?.0.skeleton

        guard let rescuer else { return (nil, nil) }

        var patient: PatientDetection?

        if let patientRect = bestHorizontalPatientRect(from: humanRects, excluding: rescuer) {
            patient = patientFromTorsoRect(
                patientRect,
                confidence: Double(patientRect.confidence),
                rescuer: rescuer
            )
        }

        if patient == nil, skeletons.count >= 2 {
            let patientSkeleton = scored
                .filter { $0.0.skeleton != rescuer }
                .max { ($0.2) < ($1.2) }?
                .0.skeleton

            if let patientSkeleton {
                patient = patientFromSkeleton(patientSkeleton, rescuer: rescuer)
            }
        }

        if patient == nil,
           let inferred = CPRChestTargetEstimator.chestTargetUnderHandsIfCPRPosture(rescuer: rescuer) {
            patient = inferred
        }

        return (rescuer, patient)
    }

    private func bestHorizontalPatientRect(
        from rects: [VNHumanObservation],
        excluding rescuer: FullBodySkeleton?
    ) -> VNHumanObservation? {
        let rescuerCenter = rescuer?.centerPoint
            ?? rescuer?.leftShoulder
            ?? rescuer?.rightShoulder

        let candidates = rects.filter { obs in
            let box = obs.boundingBox

            let isHorizontal = box.width > box.height * 1.15
            let isLargeEnough = box.width * box.height > 0.025

            var isPatientOnGround = true
            if let rescuer {
                let shoulderYs = [rescuer.leftShoulder?.y, rescuer.rightShoulder?.y].compactMap { $0 }
                if let shoulderY = shoulderYs.max() {
                    isPatientOnGround = box.midY < shoulderY - 0.02
                }
            }

            var notSameAsRescuer = true
            if let rescuerCenter {
                let center = CGPoint(x: box.midX, y: box.midY)
                let distance = hypot(center.x - rescuerCenter.x, center.y - rescuerCenter.y)
                notSameAsRescuer = distance > 0.04 || isHorizontal
            }

            return isHorizontal && isLargeEnough && isPatientOnGround && notSameAsRescuer
        }

        return candidates.max { a, b in
            horizontalPatientScore(a.boundingBox) < horizontalPatientScore(b.boundingBox)
        }
    }

    private func horizontalPatientScore(_ box: CGRect) -> Double {
        let horizontalRatio = Double(box.width / max(box.height, 0.001))
        let area = Double(box.width * box.height)
        return horizontalRatio * 2.0 + area * 8.0
    }

    private func patientFromSkeleton(
        _ patient: FullBodySkeleton,
        rescuer: FullBodySkeleton?
    ) -> PatientDetection {
        CPRChestTargetEstimator.chestTargetFromPatientSkeleton(
            patient,
            rescuer: rescuer
        )
    }

    private func patientFromTorsoRect(
        _ observation: VNHumanObservation,
        confidence: Double,
        rescuer: FullBodySkeleton?
    ) -> PatientDetection {
        CPRChestTargetEstimator.chestTargetFromHorizontalBodyBox(
            observation.boundingBox,
            rescuer: rescuer,
            confidence: confidence
        )
    }

    /// Prefer the person nearest the frame center for stable overlay lock-on.
    private func centralityScore(_ s: FullBodySkeleton) -> Double {
        guard let c = s.centerPoint ?? s.leftShoulder ?? s.rightShoulder else { return 0 }
        let dx = c.x - 0.5
        let dy = c.y - 0.5
        return max(0, 1.0 - hypot(dx, dy) * 2.2)
    }

    private func scoreAsRescuer(_ s: FullBodySkeleton) -> Double {
        var score = s.cprArmConfidence * 3.0

        // Completeness: the rescuer is the fully-visible, upright body.
        score += Double(s.allPoints.count) / 15.0 * 2.5

        // Vertical extent: a kneeling/leaning rescuer spans more height than the lying patient.
        let ys = s.allPoints.map { Double($0.1.y) }
        if let minY = ys.min(), let maxY = ys.max() {
            score += (maxY - minY) * 2.5
        }

        // Clasped hands strongly indicate the rescuer — but never required.
        if let lw = s.leftWrist, let rw = s.rightWrist {
            let wristDist = hypot(lw.x - rw.x, lw.y - rw.y)
            if wristDist < 0.12 { score += 2.5 }
            else if wristDist < 0.20 { score += 1.2 }

            if let ls = s.leftShoulder, let rs = s.rightShoulder {
                let shoulderMidY = (ls.y + rs.y) / 2
                let wristMidY = (lw.y + rw.y) / 2
                if wristMidY <= shoulderMidY + 0.12 { score += 1.5 }   // pressing down
                if wristMidY < shoulderMidY - 0.08 { score += 3.0 }    // kneeling CPR
            }
        }

        if s.leftElbow != nil, s.rightElbow != nil { score += 1.0 }
        if let center = s.centerPoint, center.y > 0.3 { score += 0.6 }

        return score
    }

    private func scoreAsPatientSkeleton(_ s: FullBodySkeleton) -> Double {
        var score = s.averageConfidence

        if let ls = s.leftShoulder, let rs = s.rightShoulder, let lh = s.leftHip, let rh = s.rightHip {
            let shoulderMidY = (ls.y + rs.y) / 2
            let hipMidY = (lh.y + rh.y) / 2
            let shoulderWidth = abs(ls.x - rs.x)
            let torsoHeight = abs(shoulderMidY - hipMidY)

            if shoulderWidth > 0.14 { score += 2.5 }
            if torsoHeight < shoulderWidth * 0.55 { score += 3 }
            if (ls.y + rs.y + lh.y + rh.y) / 4 < 0.52 { score += 2 }
        }

        if s.leftKnee != nil || s.rightKnee != nil { score += 0.8 }
        return score
    }

    private func computeQuality(
        rescuer: FullBodySkeleton?,
        patient: PatientDetection?,
        skeletonCount: Int,
        moveNetActive: Bool = false
    ) -> Double {
        var q = 0.0
        if let rescuer { q += rescuer.cprArmConfidence * 55 }
        if let patient { q += patient.confidence * 35 }
        if skeletonCount >= 1 { q += 5 }
        if rescuer != nil && patient != nil { q += 5 }
        if moveNetActive { q += 10 }
        return min(q, 100)
    }

    private func emptyScene() -> CPRSceneAnalysis {
        CPRSceneAnalysis(
            rescuer: nil,
            patient: nil,
            rescuerBox: nil,
            rescuerConfidence: 0,
            handPoses: [],
            personCount: 0,
            detectionQuality: 0,
            moveNetPose: nil,
            patientMoveNetPose: nil,
            patientCPRTarget: nil,
            timestamp: CACurrentMediaTime()
        )
    }

    // MARK: - Rescuer person box ("Person: 0.98")

    /// Full-body box derived from the smoothed rescuer skeleton extent (stable, follows tracking).
    /// Confidence prefers the matched human-rectangle objectness, else pose confidence.
    private func rescuerBoxAndConfidence(
        rescuer: FullBodySkeleton?,
        rectConfidence: Double
    ) -> (CGRect?, Double) {
        guard let rescuer else { return (nil, 0) }
        let points = rescuer.allPoints.map(\.1)
        guard !points.isEmpty else { return (nil, 0) }

        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 1
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 1

        let padX = max((maxX - minX) * 0.16, 0.03)
        let padY = max((maxY - minY) * 0.12, 0.03)

        let box = CGRect(
            x: max(0, minX - padX),
            y: max(0, minY - padY),
            width: min(1, (maxX - minX) + padX * 2),
            height: min(1, (maxY - minY) + padY * 2)
        )

        let confidence = rectConfidence > 0.01
            ? rectConfidence
            : rescuer.cprArmConfidence
        return (box, min(max(confidence, 0), 1))
    }

    // MARK: - Hand pose extraction

    /// Builds `HandPose` values, keeping the (up to 2) hands closest to the rescuer's wrists so we
    /// analyze the compressing hands, not a bystander's. Falls back to all hands when no rescuer yet.
    private func extractHands(
        _ observations: [VNHumanHandPoseObservation],
        rescuer: FullBodySkeleton?
    ) -> [HandPose] {
        let poses = observations.compactMap { extractHand(from: $0) }
        guard !poses.isEmpty else { return [] }

        guard let rescuer,
              let lw = rescuer.leftWrist,
              let rw = rescuer.rightWrist else {
            return Array(poses.prefix(2))
        }

        let wristMid = CGPoint(x: (lw.x + rw.x) / 2, y: (lw.y + rw.y) / 2)
        return poses
            .sorted {
                hypot($0.wrist.x - wristMid.x, $0.wrist.y - wristMid.y)
                    < hypot($1.wrist.x - wristMid.x, $1.wrist.y - wristMid.y)
            }
            .prefix(2)
            .map { $0 }
    }

    private func extractHand(from observation: VNHumanHandPoseObservation) -> HandPose? {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }

        func pt(_ joint: VNHumanHandPoseObservation.JointName, minConf: Float = 0.3) -> CGPoint? {
            guard let p = points[joint], p.confidence >= minConf else { return nil }
            return CGPoint(x: p.location.x, y: p.location.y)
        }

        guard let wrist = pt(.wrist, minConf: 0.25) else { return nil }

        let tipNames: [VNHumanHandPoseObservation.JointName] =
            [.thumbTip, .indexTip, .middleTip, .ringTip, .littleTip]
        let knuckleNames: [VNHumanHandPoseObservation.JointName] =
            [.thumbCMC, .indexMCP, .middleMCP, .ringMCP, .littleMCP]

        let fingertips = tipNames.compactMap { pt($0, minConf: 0.2) }
        let knuckles = knuckleNames.compactMap { pt($0, minConf: 0.2) }

        var allPts = fingertips + knuckles
        allPts.append(wrist)
        let minX = allPts.map(\.x).min() ?? wrist.x
        let maxX = allPts.map(\.x).max() ?? wrist.x
        let minY = allPts.map(\.y).min() ?? wrist.y
        let maxY = allPts.map(\.y).max() ?? wrist.y
        let box = CGRect(x: minX, y: minY, width: max(maxX - minX, 0.0001), height: max(maxY - minY, 0.0001))

        let chirality: HandPose.Chirality = {
            switch observation.chirality {
            case .left: return .left
            case .right: return .right
            default: return .unknown
            }
        }()

        return HandPose(
            chirality: chirality,
            wrist: wrist,
            fingertips: fingertips,
            knuckles: knuckles,
            boundingBox: box,
            confidence: Double(observation.confidence)
        )
    }

    // MARK: - Hand-refined wrists (paper marker C = wrist midpoint)

    private func refineSkeletonWithHands(_ skeleton: FullBodySkeleton, hands: [HandPose]) -> FullBodySkeleton {
        guard !hands.isEmpty else { return skeleton }
        var s = skeleton

        for hand in hands {
            switch hand.chirality {
            case .left:
                s.leftWrist = mergeWrist(body: s.leftWrist, hand: hand.wrist)
            case .right:
                s.rightWrist = mergeWrist(body: s.rightWrist, hand: hand.wrist)
            case .unknown:
                let dl = s.leftWrist.map { hypot($0.x - hand.wrist.x, $0.y - hand.wrist.y) } ?? .infinity
                let dr = s.rightWrist.map { hypot($0.x - hand.wrist.x, $0.y - hand.wrist.y) } ?? .infinity
                if dl <= dr {
                    s.leftWrist = mergeWrist(body: s.leftWrist, hand: hand.wrist)
                } else {
                    s.rightWrist = mergeWrist(body: s.rightWrist, hand: hand.wrist)
                }
            }
        }
        return s
    }

    private func mergeWrist(body: CGPoint?, hand: CGPoint) -> CGPoint {
        guard let body else { return hand }
        let d = hypot(body.x - hand.x, body.y - hand.y)
        if d < 0.08 { return hand }
        if d < 0.16 {
            return CGPoint(x: body.x * 0.3 + hand.x * 0.7, y: body.y * 0.3 + hand.y * 0.7)
        }
        return hand
    }
}
