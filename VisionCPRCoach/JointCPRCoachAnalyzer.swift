import CoreGraphics

/// Joint-node CPR coaching signals — wrist, elbow, hip geometry (voice never references on-screen overlays).
enum JointCPRCoachAnalyzer {

    enum HipPosture {
        case tooHigh
        case tooLow
    }

    enum WristStackPosture {
        case tooFarApart
    }

    struct JointSnapshot {
        let leftElbowAngle: Double
        let rightElbowAngle: Double
        let minElbowAngle: Double
        let wristMid: CGPoint
        let shoulderMid: CGPoint
        let hipMid: CGPoint?
        let shoulderOverWristOffset: CGFloat
        let hipPosture: HipPosture?
        let wristStack: WristStackPosture?
        let chestTarget: CGPoint
        /// For UI metrics — centered when anywhere on the acceptable chest band.
        let chestPlacement: HandPlacement
        /// True when wrists are on the chest compression area (no left/right nagging).
        let isOnChestZone: Bool
        /// Set only when hands are clearly off the chest (stomach, ribs far away, etc.).
        let clearMisplacement: HandPlacement?
    }

    struct ChestPlacementAnalysis {
        let placement: HandPlacement
        let isAcceptable: Bool
        let clearMisplacement: HandPlacement?
        let target: CGPoint
    }

    static func snapshot(joints: BodyJoints, patient: PatientDetection?) -> JointSnapshot {
        let leftElbow = elbowAngle(
            shoulder: joints.leftShoulder,
            elbow: joints.leftElbow,
            wrist: joints.leftWrist
        )
        let rightElbow = elbowAngle(
            shoulder: joints.rightShoulder,
            elbow: joints.rightElbow,
            wrist: joints.rightWrist
        )
        let wristMid = midpoint(joints.leftWrist, joints.rightWrist)
        let shoulderMid = midpoint(joints.leftShoulder, joints.rightShoulder)
        let hipMid = hipMidpoint(joints)

        let shoulderOverWristOffset = abs(shoulderMid.x - wristMid.x)
        let hipPosture = analyzeHipPosture(hipMid: hipMid, shoulderMid: shoulderMid, wristMid: wristMid)
        let wristStack = analyzeWristStack(joints: joints)
        let chest = analyzeChestPlacement(joints: joints, patient: patient)

        return JointSnapshot(
            leftElbowAngle: leftElbow,
            rightElbowAngle: rightElbow,
            minElbowAngle: min(leftElbow, rightElbow),
            wristMid: wristMid,
            shoulderMid: shoulderMid,
            hipMid: hipMid,
            shoulderOverWristOffset: shoulderOverWristOffset,
            hipPosture: hipPosture,
            wristStack: wristStack,
            chestTarget: chest.target,
            chestPlacement: chest.placement,
            isOnChestZone: chest.isAcceptable,
            clearMisplacement: chest.clearMisplacement
        )
    }

    /// Back-camera view: spoken cues use the rescuer's left/right (mirrored from image x).
    static func placementCorrectionKey(for placement: HandPlacement) -> String {
        switch placement {
        case .tooFarLeft: return "hands_left"
        case .tooFarRight: return "hands_right"
        case .tooHigh, .tooLow, .unknown: return "move_hands_center"
        case .centered: return "setup_hands_ok"
        }
    }

    static func analyzeChestPlacement(
        joints: BodyJoints,
        patient: PatientDetection?
    ) -> ChestPlacementAnalysis {
        let wristMid = midpoint(joints.leftWrist, joints.rightWrist)
        let shoulderMid = midpoint(joints.leftShoulder, joints.rightShoulder)

        if let patient {
            return analyzeChestOnPatient(
                wristMid: wristMid,
                leftWrist: joints.leftWrist,
                rightWrist: joints.rightWrist,
                patient: patient
            )
        }

        return analyzeChestWithoutPatient(
            wristMid: wristMid,
            leftWrist: joints.leftWrist,
            rightWrist: joints.rightWrist,
            leftShoulder: joints.leftShoulder,
            rightShoulder: joints.rightShoulder,
            shoulderMid: shoulderMid,
            hipMid: hipMidpoint(joints),
            neck: joints.neck
        )
    }

    private static func analyzeChestOnPatient(
        wristMid: CGPoint,
        leftWrist: CGPoint,
        rightWrist: CGPoint,
        patient: PatientDetection
    ) -> ChestPlacementAnalysis {
        let box = patient.boundingBox
        let target = patient.sternumPoint

        // Sternum-centered band so blue wrist nodes align with chest center on the green box.
        let bandWidth = box.width * 0.42
        let bandHeight = box.height * 0.48
        let chestBand = CGRect(
            x: target.x - bandWidth / 2,
            y: target.y - bandHeight * 0.42,
            width: bandWidth,
            height: bandHeight
        )

        if wristsInBand(chestBand, wristMid: wristMid, left: leftWrist, right: rightWrist) {
            return acceptable(at: target)
        }

        if let horizontal = horizontalPlacementTowardChest(wristMid: wristMid, target: target) {
            return clearlyWrong(horizontal, target: target)
        }

        return acceptable(at: target)
    }

    /// Left/right only — rescuer-facing cues (back camera mirror).
    private static func horizontalPlacementTowardChest(
        wristMid: CGPoint,
        target: CGPoint,
        tolerance: CGFloat = 0.020
    ) -> HandPlacement? {
        let dx = wristMid.x - target.x
        if abs(dx) <= tolerance { return nil }
        return dx < 0 ? .tooFarLeft : .tooFarRight
    }

    /// Only re-correct hand placement after setup when hands leave the chest region entirely.
    static func drasticMisplacement(
        joints: BodyJoints,
        patient: PatientDetection?
    ) -> HandPlacement? {
        guard let patient else { return nil }
        let wristMid = midpoint(joints.leftWrist, joints.rightWrist)
        let box = patient.boundingBox
        let loose = box.insetBy(dx: -box.width * 0.12, dy: -box.height * 0.12)
        guard !loose.contains(wristMid) else { return nil }

        let analysis = analyzeChestPlacement(joints: joints, patient: patient)
        return analysis.clearMisplacement ?? analysis.placement
    }

    static func directionalPlacementHint(
        joints: BodyJoints,
        patient: PatientDetection?
    ) -> HandPlacement? {
        guard let patient else { return nil }
        let wristMid = midpoint(joints.leftWrist, joints.rightWrist)
        let analysis = analyzeChestPlacement(joints: joints, patient: patient)
        if analysis.isAcceptable { return nil }
        if let horizontal = horizontalPlacementTowardChest(
            wristMid: wristMid,
            target: analysis.target
        ) {
            return horizontal
        }
        if let clear = analysis.clearMisplacement,
           clear == .tooFarLeft || clear == .tooFarRight {
            return clear
        }
        return nil
    }

    private static func analyzeChestWithoutPatient(
        wristMid: CGPoint,
        leftWrist: CGPoint,
        rightWrist: CGPoint,
        leftShoulder: CGPoint,
        rightShoulder: CGPoint,
        shoulderMid: CGPoint,
        hipMid: CGPoint?,
        neck: CGPoint?
    ) -> ChestPlacementAnalysis {
        let target = estimatedChestTarget(shoulderMid: shoulderMid, hipMid: hipMid, neck: neck)

        let shoulderWidth = max(
            0.12,
            hypot(leftShoulder.x - rightShoulder.x, leftShoulder.y - rightShoulder.y)
        )
        let wristGap = hypot(leftWrist.x - rightWrist.x, leftWrist.y - rightWrist.y)
        if wristGap >= shoulderWidth * 0.95 {
            return clearlyWrong(.unknown, target: target)
        }

        let verticalDrop = shoulderMid.y - wristMid.y
        if verticalDrop > 0.30 {
            return clearlyWrong(.tooLow, target: target)
        }
        if verticalDrop < 0.05 {
            return clearlyWrong(.tooHigh, target: target)
        }

        if let hipMid {
            let torsoSpan = max(shoulderMid.y - hipMid.y, 0.06)
            let relativeHeight = (wristMid.y - hipMid.y) / torsoSpan
            if relativeHeight < 0.34 {
                return clearlyWrong(.tooLow, target: target)
            }
            if relativeHeight > 0.68 {
                return clearlyWrong(.tooHigh, target: target)
            }
            if relativeHeight >= 0.38, relativeHeight <= 0.62 {
                return acceptable(at: target)
            }
        }

        let horizontalOffset = abs(wristMid.x - shoulderMid.x)
        if horizontalOffset > 0.16 {
            return clearlyWrong(wristMid.x < shoulderMid.x ? .tooFarLeft : .tooFarRight, target: target)
        }

        if verticalDrop >= 0.08, verticalDrop <= 0.24, horizontalOffset <= 0.13 {
            return acceptable(at: target)
        }

        let dist = hypot(wristMid.x - target.x, wristMid.y - target.y)
        if dist > 0.16 {
            return clearlyWrong(dominantOffPlacement(wristMid: wristMid, target: target), target: target)
        }

        return acceptable(at: target)
    }

    private static func wristsInBand(
        _ band: CGRect,
        wristMid: CGPoint,
        left: CGPoint,
        right: CGPoint
    ) -> Bool {
        band.contains(wristMid) || band.contains(left) || band.contains(right)
    }

    private static func acceptable(at target: CGPoint) -> ChestPlacementAnalysis {
        ChestPlacementAnalysis(
            placement: .centered,
            isAcceptable: true,
            clearMisplacement: nil,
            target: target
        )
    }

    private static func clearlyWrong(_ placement: HandPlacement, target: CGPoint) -> ChestPlacementAnalysis {
        ChestPlacementAnalysis(
            placement: placement,
            isAcceptable: false,
            clearMisplacement: placement,
            target: target
        )
    }

    private static func dominantOffPlacement(wristMid: CGPoint, target: CGPoint) -> HandPlacement {
        horizontalPlacementTowardChest(wristMid: wristMid, target: target)
            ?? .tooFarLeft
    }

    private static func estimatedChestTarget(
        shoulderMid: CGPoint,
        hipMid: CGPoint?,
        neck: CGPoint?
    ) -> CGPoint {
        if let hipMid {
            let span = shoulderMid.y - hipMid.y
            return CGPoint(x: shoulderMid.x, y: hipMid.y + span * 0.52)
        }
        if let neck {
            return CGPoint(x: shoulderMid.x, y: (shoulderMid.y + neck.y) / 2 - 0.02)
        }
        return CGPoint(x: shoulderMid.x, y: shoulderMid.y - 0.14)
    }

    static func handsReadyForSetup(
        joints: BodyJoints,
        snapshot: JointSnapshot,
        patientDetected: Bool
    ) -> Bool {
        let shoulderWidth = max(
            0.12,
            hypot(
                joints.leftShoulder.x - joints.rightShoulder.x,
                joints.leftShoulder.y - joints.rightShoulder.y
            )
        )
        let wristGap = hypot(
            joints.leftWrist.x - joints.rightWrist.x,
            joints.leftWrist.y - joints.rightWrist.y
        )
        guard wristGap < shoulderWidth * 0.95 else { return false }

        let shouldersAboveWrists = snapshot.shoulderMid.y - snapshot.wristMid.y
        guard shouldersAboveWrists > 0.04 else { return false }

        if patientDetected {
            return snapshot.isOnChestZone
        }
        return true
    }

    static func elbowAngle(shoulder: CGPoint, elbow: CGPoint, wrist: CGPoint) -> Double {
        let upper = CGVector(dx: shoulder.x - elbow.x, dy: shoulder.y - elbow.y)
        let lower = CGVector(dx: wrist.x - elbow.x, dy: wrist.y - elbow.y)

        let dot = upper.dx * lower.dx + upper.dy * lower.dy
        let magUpper = hypot(upper.dx, upper.dy)
        let magLower = hypot(lower.dx, lower.dy)
        guard magUpper > 0.0001, magLower > 0.0001 else { return 0 }

        let cosTheta = max(-1, min(1, dot / (magUpper * magLower)))
        return acos(cosTheta) * 180 / .pi
    }

    static func analyzeHipPosture(
        hipMid: CGPoint?,
        shoulderMid: CGPoint,
        wristMid: CGPoint
    ) -> HipPosture? {
        guard let hipMid else { return nil }

        let shouldersAboveWrists = shoulderMid.y - wristMid.y
        guard shouldersAboveWrists > 0.04 else { return nil }

        let hipsAboveShoulders = hipMid.y - shoulderMid.y

        // Serious posture errors only — avoid nagging normal kneeling CPR.
        if hipsAboveShoulders > 0.28 {
            return .tooHigh
        }

        if shouldersAboveWrists < 0.04, hipsAboveShoulders < -0.30 {
            return .tooLow
        }

        return nil
    }

    static func analyzeWristStack(joints: BodyJoints) -> WristStackPosture? {
        let shoulderWidth = max(
            0.12,
            hypot(
                joints.leftShoulder.x - joints.rightShoulder.x,
                joints.leftShoulder.y - joints.rightShoulder.y
            )
        )
        let dx = abs(joints.leftWrist.x - joints.rightWrist.x)
        let dy = abs(joints.leftWrist.y - joints.rightWrist.y)
        let wristGap = hypot(dx, dy)

        // Side-by-side (horizontal) hands — not stacked for CPR.
        if dx > shoulderWidth * 0.30, dx > dy * 0.75 {
            return .tooFarApart
        }
        if wristGap > shoulderWidth * 0.62 {
            return .tooFarApart
        }
        return nil
    }

    static func wristsStackedForSetup(joints: BodyJoints) -> Bool {
        let shoulderWidth = max(
            0.12,
            hypot(
                joints.leftShoulder.x - joints.rightShoulder.x,
                joints.leftShoulder.y - joints.rightShoulder.y
            )
        )
        let dx = abs(joints.leftWrist.x - joints.rightWrist.x)
        let dy = abs(joints.leftWrist.y - joints.rightWrist.y)
        let wristGap = hypot(dx, dy)
        return dx < shoulderWidth * 0.28 && wristGap < shoulderWidth * 0.50
    }

    /// Repeat elbow cue only when clearly bent (high confidence).
    static func isConfidentlyBentElbows(snapshot: JointSnapshot) -> Bool {
        snapshot.minElbowAngle < CPRGuidelines.setupElbowAngleMin
    }

    static func isConfidentHipHigh(snapshot: JointSnapshot) -> Bool {
        guard let hipMid = snapshot.hipMid else { return false }
        return hipMid.y - snapshot.shoulderMid.y > 0.32
    }

    static func isConfidentHipLow(snapshot: JointSnapshot) -> Bool {
        guard let hipMid = snapshot.hipMid else { return false }
        let shouldersAboveWrists = snapshot.shoulderMid.y - snapshot.wristMid.y
        return shouldersAboveWrists < 0.035 && hipMid.y - snapshot.shoulderMid.y < -0.32
    }

    static func isConfidentWristsApart(snapshot: JointSnapshot, joints: BodyJoints) -> Bool {
        analyzeWristStack(joints: joints) == .tooFarApart
    }

    private static func hipMidpoint(_ joints: BodyJoints) -> CGPoint? {
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

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}
