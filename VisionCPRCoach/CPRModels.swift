import Foundation
import CoreGraphics

/// Full 14+ joint skeleton from Vision (17-keypoint body pose on-device).
struct FullBodySkeleton: Equatable {
    var nose: CGPoint?
    var neck: CGPoint?
    var leftShoulder: CGPoint?
    var rightShoulder: CGPoint?
    var leftElbow: CGPoint?
    var rightElbow: CGPoint?
    var leftWrist: CGPoint?
    var rightWrist: CGPoint?
    var leftHip: CGPoint?
    var rightHip: CGPoint?
    var leftKnee: CGPoint?
    var rightKnee: CGPoint?
    var leftAnkle: CGPoint?
    var rightAnkle: CGPoint?
    var root: CGPoint?
    var averageConfidence: Double

    var allPoints: [(String, CGPoint)] {
        var result: [(String, CGPoint)] = []
        if let nose { result.append(("nose", nose)) }
        if let neck { result.append(("neck", neck)) }
        if let leftShoulder { result.append(("leftShoulder", leftShoulder)) }
        if let rightShoulder { result.append(("rightShoulder", rightShoulder)) }
        if let leftElbow { result.append(("leftElbow", leftElbow)) }
        if let rightElbow { result.append(("rightElbow", rightElbow)) }
        if let leftWrist { result.append(("leftWrist", leftWrist)) }
        if let rightWrist { result.append(("rightWrist", rightWrist)) }
        if let leftHip { result.append(("leftHip", leftHip)) }
        if let rightHip { result.append(("rightHip", rightHip)) }
        if let leftKnee { result.append(("leftKnee", leftKnee)) }
        if let rightKnee { result.append(("rightKnee", rightKnee)) }
        if let leftAnkle { result.append(("leftAnkle", leftAnkle)) }
        if let rightAnkle { result.append(("rightAnkle", rightAnkle)) }
        if let root { result.append(("root", root)) }
        return result
    }

    /// CPR overlay joints: shoulders, elbows, wrists, hips (both sides).
    var overlayJointCount: Int {
        [leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist, leftHip, rightHip]
            .compactMap { $0 }
            .count
    }

    /// True when enough joints are present to draw a connected skeleton (not stray dots).
    var isOverlayVisible: Bool {
        overlayJointCount >= 3 && (leftShoulder != nil || rightShoulder != nil)
    }

    func toBodyJoints() -> BodyJoints? {
        guard
            let ls = leftShoulder, let rs = rightShoulder,
            let le = leftElbow, let re = rightElbow,
            let lw = leftWrist, let rw = rightWrist
        else { return nil }

        return BodyJoints(
            leftShoulder: ls,
            rightShoulder: rs,
            leftElbow: le,
            rightElbow: re,
            leftWrist: lw,
            rightWrist: rw,
            leftHip: leftHip,
            rightHip: rightHip,
            neck: neck,
            averageConfidence: averageConfidence
        )
    }
}

struct PatientDetection: Equatable {
    /// Normalized 0–1 bounding box (Vision coordinate space, origin bottom-left).
    let boundingBox: CGRect
    let sternumPoint: CGPoint
    let confidence: Double
    let label: String
}

extension PatientDetection {
    init(target: PatientCPRTarget) {
        self.init(
            boundingBox: target.chestBox,
            sternumPoint: target.sternumPoint,
            confidence: target.confidence,
            label: "patient_label"
        )
    }
}

/// A detected hand from VNDetectHumanHandPoseRequest, normalized Vision space (origin bottom-left).
struct HandPose: Equatable {
    enum Chirality: String { case left, right, unknown }

    let chirality: Chirality
    let wrist: CGPoint
    /// Fingertip points present this frame (thumb, index, middle, ring, little — any subset).
    let fingertips: [CGPoint]
    /// Knuckle (MCP) points, used as a flat-palm reference.
    let knuckles: [CGPoint]
    let boundingBox: CGRect
    let confidence: Double

    /// Mean fingertip → wrist distance normalized by hand bbox diagonal.
    /// High ≈ open/extended fingers (correct heel-of-palm), low ≈ clenched fist.
    var fingerExtension: Double {
        guard !fingertips.isEmpty else { return 1 }
        let diag = max(hypot(boundingBox.width, boundingBox.height), 0.0001)
        let mean = fingertips
            .map { hypot($0.x - wrist.x, $0.y - wrist.y) }
            .reduce(0, +) / Double(fingertips.count)
        return min(mean / diag, 2.0)
    }
}

struct CPRSceneAnalysis: Equatable {
    let rescuer: FullBodySkeleton?
    let patient: PatientDetection?
    /// Normalized rescuer person box (Vision space) + its detection confidence ("Person: 0.98").
    let rescuerBox: CGRect?
    let rescuerConfidence: Double
    let handPoses: [HandPose]
    let personCount: Int
    let detectionQuality: Double
    /// Raw MoveNet output for live overlay (Python draw_pose).
    let moveNetPose: MoveNetPose?
    /// Patient-only MoveNet pass (cropped to horizontal body region).
    let patientMoveNetPose: MoveNetPose?
    /// Anatomical CPR target built from patient shoulder/hip keypoints.
    let patientCPRTarget: PatientCPRTarget?
    let timestamp: TimeInterval

    var rescuerJoints: BodyJoints? { rescuer?.toBodyJoints() }

    var overlayRescuer: FullBodySkeleton? {
        guard let rescuer, rescuer.isOverlayVisible else { return nil }
        return rescuer
    }

    var isReadyForCoaching: Bool {
        overlayRescuer != nil && patient != nil
    }
}

// MARK: - CPR Error Action Recognition (CPR-Coach 14-class taxonomy, on-device)

/// The single-error action classes from the reference recognition system, plus `correct`.
/// Each is detected adaptively — a class is only asserted when the joints/hands it needs are visible.
enum CPRErrorAction: String, CaseIterable, Equatable {
    case correct
    case overlapHands
    case clenchingHands
    case singleHand
    case bendingArms
    case tiltingArms
    case jumpPressing
    case squatting
    case standing
    case wrongPosition
    case insufficientPressing
    case slowFrequency
    case excessivePressing
    case randomPositionPressing

    var localizationKey: String { "action_\(rawValue.snakeCased)" }
    var fixKey: String { "actionfix_\(rawValue.snakeCased)" }
    var isError: Bool { self != .correct }

    /// Clinical severity (higher = more urgent to surface). Used to pick the headline action.
    var severity: Int {
        switch self {
        case .correct: return 0
        case .randomPositionPressing: return 3
        case .overlapHands: return 3
        case .clenchingHands: return 4
        case .tiltingArms: return 5
        case .squatting: return 5
        case .jumpPressing: return 6
        case .standing: return 7
        case .bendingArms: return 7
        case .slowFrequency: return 8
        case .excessivePressing: return 8
        case .insufficientPressing: return 9
        case .singleHand: return 9
        case .wrongPosition: return 10
        }
    }
}

private extension String {
    /// "overlapHands" -> "overlap_hands"
    var snakeCased: String {
        reduce(into: "") { acc, ch in
            if ch.isUppercase {
                acc.append("_")
                acc.append(Character(ch.lowercased()))
            } else {
                acc.append(ch)
            }
        }
    }
}

/// Result of one recognition pass — mirrors the reference "Action: confidence" + "Person: confidence".
struct ActionRecognitionResult: Equatable {
    let primary: CPRErrorAction
    /// Final displayed confidence in [0,1], already gated by the composite confidence score.
    let confidence: Double
    /// Per-class raw confidences (pre-gating) for any class that fired.
    let scores: [CPRErrorAction: Double]
    /// Objectness term — pose/detection confidence of the rescuer.
    let objectness: Double
    /// Temporal-consistency term — agreement of recent frames on the primary class.
    let temporalConsistency: Double
    /// All firing error classes, most-critical first.
    let activeErrors: [CPRErrorAction]

    /// Composite confidence score: CS = objectness × temporal_consistency.
    var confidenceScore: Double { objectness * temporalConsistency }

    static let idle = ActionRecognitionResult(
        primary: .correct,
        confidence: 0,
        scores: [:],
        objectness: 0,
        temporalConsistency: 0,
        activeErrors: []
    )
}

struct BodyJoints {
    let leftShoulder: CGPoint
    let rightShoulder: CGPoint
    let leftElbow: CGPoint
    let rightElbow: CGPoint
    let leftWrist: CGPoint
    let rightWrist: CGPoint
    let leftHip: CGPoint?
    let rightHip: CGPoint?
    let neck: CGPoint?
    let averageConfidence: Double
}

struct CPRMetrics {
    let elbowAngle: Double
    let compressionsPerMinute: Double
    let handPlacement: HandPlacement
    let motionAmplitude: Double
    let estimatedDepthCm: Double
    let depthQuality: DepthEstimate
    let recoilQuality: RecoilQuality
    let overallQuality: CompressionQuality
    let confidence: Double
    let pressureScore: Double
    /// True when wrist motion shows an active compression pattern.
    let compressionActive: Bool
    /// 0–1 confidence that CPM estimate is reliable enough to coach rate.
    let rateConfidence: Double
    /// 0–1 confidence that depth estimate is reliable enough to coach depth.
    let depthConfidence: Double
}

enum HandPlacement: String {
    case centered = "Centered"
    case tooFarLeft = "Too Far Left"
    case tooFarRight = "Too Far Right"
    case tooHigh = "Too High"
    case tooLow = "Too Low"
    case unknown = "Unknown"
}

enum CPRFlowState: String, CaseIterable {
    case ready = "Ready"
    case checkResponsiveness = "Check Responsiveness"
    case checkBreathing = "Check Breathing"
    case callEmergency = "Call Emergency Services"
    case startCompressions = "Start Compressions"
    case activeCoaching = "Active Coaching"
    case paused = "Paused"
    case finished = "Finished"
}

enum EmergencyAnswer: String, CaseIterable {
    case yes = "Yes"
    case no = "No"
    case unsure = "Unsure"
}

struct EmergencyAssessment {
    let isResponsive: EmergencyAnswer?
    let isBreathingNormally: EmergencyAnswer?
    let emergencyCalled: EmergencyAnswer?
    let shouldStartCPR: Bool
}

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: ChatRole
    let text: String
    let timestamp: Date

    enum ChatRole: String {
        case user
        case coach
        case system
    }
}

struct HospitalPlace: Identifiable, Equatable {
    let id: String
    let name: String
    let address: String
    let detailText: String?
    let latitude: Double
    let longitude: Double
    let distanceMeters: Double?

    init(
        id: String,
        name: String,
        address: String,
        latitude: Double,
        longitude: Double,
        distanceMeters: Double?,
        detailText: String? = nil
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.detailText = detailText
        self.latitude = latitude
        self.longitude = longitude
        self.distanceMeters = distanceMeters
    }

    var distanceText: String {
        guard let distanceMeters else { return "—" }
        if distanceMeters < 1000 {
            return String(format: "%.0f m", distanceMeters)
        }
        return String(format: "%.1f km", distanceMeters / 1000)
    }
}

struct CalibrationProfile: Codable {
    var baselineAmplitude: Double
    var baselineDepthCm: Double
    var isCalibrated: Bool

    static let `default` = CalibrationProfile(
        baselineAmplitude: 0.04,
        baselineDepthCm: 5.5,
        isCalibrated: false
    )
}
