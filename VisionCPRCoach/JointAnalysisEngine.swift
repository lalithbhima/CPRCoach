import Foundation
import CoreGraphics

/// Analyzes rescuer joint nodes relative to the green-box chest target (Vision-based geometry).
struct JointAnalysis {
    let chestTarget: CGPoint
    let wristMidpoint: CGPoint
    let shoulderMidpoint: CGPoint
    let horizontalOffset: Double
    let verticalOffset: Double
    let armSymmetry: Double
    let postureScore: Double
    let alignmentIssue: String?
    let nodeSummary: String
}

enum JointAnalysisEngine {
    static func analyze(joints: BodyJoints, metrics: CPRMetrics, chestTarget: CGPoint? = nil) -> JointAnalysis {
        let wristMid = midpoint(joints.leftWrist, joints.rightWrist)
        let shoulderMid = midpoint(joints.leftShoulder, joints.rightShoulder)
        let hipMid = hipMid(joints)

        let target = chestTarget ?? chestCompressionLandmark(shoulderMid: shoulderMid, hipMid: hipMid, neck: joints.neck)
        let hOffset = Double(wristMid.x - target.x)
        let vOffset = Double(wristMid.y - target.y)

        let leftArmLen = distance(joints.leftShoulder, joints.leftWrist)
        let rightArmLen = distance(joints.rightShoulder, joints.rightWrist)
        let symmetry = 1.0 - min(abs(leftArmLen - rightArmLen) / max(leftArmLen, rightArmLen, 0.001), 1.0)

        var postureScore = metrics.confidence * 30
        if metrics.handPlacement == .centered { postureScore += 25 }
        if metrics.elbowAngle >= CPRGuidelines.targetElbowAngleMin { postureScore += 20 }
        if metrics.depthQuality == .adequate { postureScore += 15 }
        if metrics.recoilQuality == .full { postureScore += 10 }
        postureScore = min(postureScore, 100)

        let alignmentIssue = alignmentIssueText(
            placement: metrics.handPlacement,
            hOffset: hOffset,
            elbow: metrics.elbowAngle,
            depth: metrics.depthQuality
        )

        let nodeSummary = """
        Wrists(L:\(fmt(joints.leftWrist)), R:\(fmt(joints.rightWrist))) \
        Chest target:\(fmt(target)) \
        Offset h:\(String(format: "%.2f", hOffset)) v:\(String(format: "%.2f", vOffset)) \
        Elbow \(Int(metrics.elbowAngle))° CPM \(Int(metrics.compressionsPerMinute)) \
        Depth \(String(format: "%.1f", metrics.estimatedDepthCm))cm \
        Confidence \(Int(metrics.confidence * 100))%
        """

        return JointAnalysis(
            chestTarget: target,
            wristMidpoint: wristMid,
            shoulderMidpoint: shoulderMid,
            horizontalOffset: hOffset,
            verticalOffset: vOffset,
            armSymmetry: symmetry,
            postureScore: postureScore,
            alignmentIssue: alignmentIssue,
            nodeSummary: nodeSummary
        )
    }

    private static func chestCompressionLandmark(shoulderMid: CGPoint, hipMid: CGPoint?, neck: CGPoint?) -> CGPoint {
        if let hipMid {
            return CGPoint(
                x: shoulderMid.x,
                y: shoulderMid.y + (hipMid.y - shoulderMid.y) * 0.38
            )
        }
        if let neck {
            return CGPoint(x: shoulderMid.x, y: (shoulderMid.y + neck.y) / 2)
        }
        return shoulderMid
    }

    private static func alignmentIssueText(
        placement: HandPlacement,
        hOffset: Double,
        elbow: Double,
        depth: DepthEstimate
    ) -> String? {
        switch placement {
        case .tooFarLeft: return "Wrist nodes are left of the green-box chest center"
        case .tooFarRight: return "Wrist nodes are right of the green-box chest center"
        case .tooHigh: return "Wrist nodes are above the chest compression zone"
        case .tooLow: return "Wrist nodes are below the chest compression zone"
        case .unknown: return "Insufficient joint confidence for hand placement"
        case .centered:
            if elbow < CPRGuidelines.targetElbowAngleMin { return "Bent elbows — shoulder-elbow-wrist angle too acute" }
            if depth == .tooShallow { return "Wrist vertical displacement indicates shallow compressions" }
            if depth == .tooDeep { return "Wrist displacement exceeds recommended depth envelope" }
            return nil
        }
    }

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    private static func hipMid(_ joints: BodyJoints) -> CGPoint? {
        switch (joints.leftHip, joints.rightHip) {
        case let (.some(l), .some(r)): return midpoint(l, r)
        default: return nil
        }
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(Double(a.x - b.x), Double(a.y - b.y))
    }

    private static func fmt(_ p: CGPoint) -> String {
        "(\(String(format: "%.2f", p.x)),\(String(format: "%.2f", p.y)))"
    }
}
