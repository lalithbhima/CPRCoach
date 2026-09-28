import Foundation
import CoreGraphics

struct PatientCPRTarget: Equatable {
    let leftShoulder: CGPoint
    let rightShoulder: CGPoint
    let leftHip: CGPoint
    let rightHip: CGPoint

    let torsoBox: CGRect
    let chestBox: CGRect
    let sternumPoint: CGPoint
    let confidence: Double
}

struct PatientCPRTargetBuilder {

    /// All coordinates must be normalized Vision-style coordinates.
    /// Origin is bottom-left.
    static func build(
        leftShoulder: CGPoint,
        rightShoulder: CGPoint,
        leftHip: CGPoint,
        rightHip: CGPoint,
        confidence: Double
    ) -> PatientCPRTarget {
        let shoulderMid = CGPoint(
            x: (leftShoulder.x + rightShoulder.x) / 2,
            y: (leftShoulder.y + rightShoulder.y) / 2
        )

        let hipMid = CGPoint(
            x: (leftHip.x + rightHip.x) / 2,
            y: (leftHip.y + rightHip.y) / 2
        )

        // CPR compression target: center/lower sternum approximation.
        // This is the stable geometric target for a CPR training demo.
        let sternum = CGPoint(
            x: shoulderMid.x + (hipMid.x - shoulderMid.x) * 0.35,
            y: shoulderMid.y + (hipMid.y - shoulderMid.y) * 0.35
        )

        let xs = [leftShoulder.x, rightShoulder.x, leftHip.x, rightHip.x]
        let ys = [leftShoulder.y, rightShoulder.y, leftHip.y, rightHip.y]

        let minX = xs.min() ?? 0.35
        let maxX = xs.max() ?? 0.65
        let minY = ys.min() ?? 0.35
        let maxY = ys.max() ?? 0.65

        let torsoBox = clamp(CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        ).insetBy(dx: -0.04, dy: -0.04))

        let shoulderWidth = hypot(
            leftShoulder.x - rightShoulder.x,
            leftShoulder.y - rightShoulder.y
        )

        let torsoLength = hypot(
            shoulderMid.x - hipMid.x,
            shoulderMid.y - hipMid.y
        )

        let chestWidth = min(max(shoulderWidth * 0.80, 0.14), 0.34)
        let chestHeight = min(max(torsoLength * 0.32, 0.10), 0.24)

        let chestBox = clamp(CGRect(
            x: sternum.x - chestWidth / 2,
            y: sternum.y - chestHeight / 2,
            width: chestWidth,
            height: chestHeight
        ))

        return PatientCPRTarget(
            leftShoulder: leftShoulder,
            rightShoulder: rightShoulder,
            leftHip: leftHip,
            rightHip: rightHip,
            torsoBox: torsoBox,
            chestBox: chestBox,
            sternumPoint: clamp(sternum),
            confidence: confidence
        )
    }

    private static func clamp(_ rect: CGRect) -> CGRect {
        let x = max(0, min(rect.minX, 1))
        let y = max(0, min(rect.minY, 1))
        let w = max(0.001, min(rect.width, 1 - x))
        let h = max(0.001, min(rect.height, 1 - y))
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private static func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: max(0, min(point.x, 1)),
            y: max(0, min(point.y, 1))
        )
    }
}
