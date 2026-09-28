import CoreGraphics

/// MoveNet 17 keypoints — indices match `live_movenet_cpr.py` KEYPOINT_DICT.
enum MoveNetJoint: Int, CaseIterable {
    case nose = 0
    case leftEye = 1
    case rightEye = 2
    case leftEar = 3
    case rightEar = 4
    case leftShoulder = 5
    case rightShoulder = 6
    case leftElbow = 7
    case rightElbow = 8
    case leftWrist = 9
    case rightWrist = 10
    case leftHip = 11
    case rightHip = 12
    case leftKnee = 13
    case rightKnee = 14
    case leftAnkle = 15
    case rightAnkle = 16

    var pythonName: String {
        switch self {
        case .nose: return "nose"
        case .leftEye: return "left_eye"
        case .rightEye: return "right_eye"
        case .leftEar: return "left_ear"
        case .rightEar: return "right_ear"
        case .leftShoulder: return "left_shoulder"
        case .rightShoulder: return "right_shoulder"
        case .leftElbow: return "left_elbow"
        case .rightElbow: return "right_elbow"
        case .leftWrist: return "left_wrist"
        case .rightWrist: return "right_wrist"
        case .leftHip: return "left_hip"
        case .rightHip: return "right_hip"
        case .leftKnee: return "left_knee"
        case .rightKnee: return "right_knee"
        case .leftAnkle: return "left_ankle"
        case .rightAnkle: return "right_ankle"
        }
    }
}

/// Python `keypoint_to_pixel`: x_px = x * width, y_px = y * height (top-left origin).
struct MoveNetKeypoint: Equatable {
    let joint: MoveNetJoint
    let x: CGFloat
    let y: CGFloat
    let confidence: Float
}

struct MoveNetPose: Equatable {
    let keypoints: [MoveNetKeypoint]
    let frameWidth: Int
    let frameHeight: Int
    let inferenceMs: Double

    func keypoint(_ joint: MoveNetJoint, minConfidence: Float = MoveNetPoseEstimator.minKeypointScore) -> MoveNetKeypoint? {
        keypoints.first { $0.joint == joint && $0.confidence >= minConfidence }
    }

    /// Metrics / overlay pipeline (Vision bottom-left normalized).
    func toFullBodySkeleton() -> FullBodySkeleton {
        func pt(_ j: MoveNetJoint, minConf: Float) -> CGPoint? {
            guard let kp = keypoint(j, minConfidence: minConf) else { return nil }
            return CGPoint(x: kp.x, y: 1.0 - kp.y)
        }

        let core: Float = 0.15
        let limb: Float = 0.12
        let ext: Float = 0.10

        let keyConfs = [
            MoveNetJoint.leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
            .leftWrist, .rightWrist, .leftHip, .rightHip
        ].compactMap { keypoint($0, minConfidence: limb)?.confidence }.map(Double.init)
        let avg = keyConfs.isEmpty
            ? 0
            : keyConfs.reduce(0, +) / Double(keyConfs.count)

        return FullBodySkeleton(
            nose: pt(.nose, minConf: ext),
            neck: neckEstimate(),
            leftShoulder: pt(.leftShoulder, minConf: core),
            rightShoulder: pt(.rightShoulder, minConf: core),
            leftElbow: pt(.leftElbow, minConf: limb),
            rightElbow: pt(.rightElbow, minConf: limb),
            leftWrist: pt(.leftWrist, minConf: limb),
            rightWrist: pt(.rightWrist, minConf: limb),
            leftHip: pt(.leftHip, minConf: core),
            rightHip: pt(.rightHip, minConf: core),
            leftKnee: pt(.leftKnee, minConf: limb),
            rightKnee: pt(.rightKnee, minConf: limb),
            leftAnkle: pt(.leftAnkle, minConf: ext),
            rightAnkle: pt(.rightAnkle, minConf: ext),
            root: hipMidpoint(),
            averageConfidence: avg
        )
    }

    private func neckEstimate() -> CGPoint? {
        guard let ls = keypoint(.leftShoulder), let rs = keypoint(.rightShoulder) else { return nil }
        let midX = (ls.x + rs.x) / 2
        let midYVision = 1.0 - (ls.y + rs.y) / 2
        if let nose = keypoint(.nose) {
            let noseYVision = 1.0 - nose.y
            return CGPoint(x: midX, y: (midYVision + noseYVision) / 2)
        }
        return CGPoint(x: midX, y: midYVision)
    }

    private func hipMidpoint() -> CGPoint? {
        guard let lh = keypoint(.leftHip), let rh = keypoint(.rightHip) else { return nil }
        return CGPoint(x: (lh.x + rh.x) / 2, y: 1.0 - (lh.y + rh.y) / 2)
    }
}