import Foundation
import CoreGraphics

struct CPRChestTargetEstimator {

    /// Coordinates are Vision-style normalized coordinates (origin bottom-left).
    static func chestTargetFromPatientSkeleton(
        _ patient: FullBodySkeleton,
        rescuer: FullBodySkeleton?
    ) -> PatientDetection {
        if
            let ls = patient.leftShoulder,
            let rs = patient.rightShoulder,
            let lh = patient.leftHip,
            let rh = patient.rightHip
        {
            let shoulderMid = midpoint(ls, rs)
            let hipMid = midpoint(lh, rh)

            let xs = [ls.x, rs.x, lh.x, rh.x]
            let ys = [ls.y, rs.y, lh.y, rh.y]
            var torsoBox = clamp(CGRect(
                x: xs.min() ?? 0,
                y: ys.min() ?? 0,
                width: (xs.max() ?? 1) - (xs.min() ?? 0),
                height: (ys.max() ?? 1) - (ys.min() ?? 0)
            ).insetBy(dx: -0.03, dy: -0.03))

            torsoBox = anchorChestBelowArms(torsoBox, rescuer: rescuer)

            let sternum = sternumPoint(
                shoulderMid: shoulderMid,
                hipMid: hipMid,
                chestBox: torsoBox
            )

            return PatientDetection(
                boundingBox: torsoBox,
                sternumPoint: sternum,
                confidence: min(max(patient.averageConfidence, 0.45), 0.95),
                label: "patient_label"
            )
        }

        return chestTargetFromHorizontalBodyBox(
            patientBox(patient),
            rescuer: rescuer,
            confidence: patient.averageConfidence
        )
    }

    /// Full chest region on a horizontal patient/manikin — stable, below rescuer arms.
    static func chestTargetFromHorizontalBodyBox(
        _ bodyBox: CGRect,
        rescuer: FullBodySkeleton?,
        confidence: Double
    ) -> PatientDetection {
        let box = bodyBox.standardized
        let isHorizontal = box.width > box.height * 1.10

        let chestBox: CGRect
        if isHorizontal {
            // Lying patient: chest spans the middle of the body along its long axis, full visible thickness.
            let alongMin = box.minX + box.width * 0.22
            let alongMax = box.minX + box.width * 0.72
            let acrossMin = box.minY + box.height * 0.06
            let acrossMax = box.maxY - box.height * 0.06
            chestBox = clamp(CGRect(
                x: alongMin,
                y: acrossMin,
                width: alongMax - alongMin,
                height: acrossMax - acrossMin
            ))
        } else {
            // Upright / ambiguous fallback: upper torso band.
            let chestHeight = min(max(box.height * 0.42, 0.12), 0.34)
            let chestWidth = min(max(box.width * 0.82, 0.16), 0.40)
            let chestMinY = box.minY + box.height * 0.38
            chestBox = clamp(CGRect(
                x: box.midX - chestWidth / 2,
                y: chestMinY,
                width: chestWidth,
                height: chestHeight
            ))
        }

        let anchored = anchorChestBelowArms(chestBox, rescuer: rescuer)
        let sternum = sternumPoint(
            shoulderMid: CGPoint(x: anchored.midX, y: anchored.maxY - anchored.height * 0.22),
            hipMid: CGPoint(x: anchored.midX, y: anchored.minY + anchored.height * 0.18),
            chestBox: anchored
        )

        return PatientDetection(
            boundingBox: anchored,
            sternumPoint: sternum,
            confidence: min(max(confidence, 0.35), 0.95),
            label: "patient_label"
        )
    }

    /// Green CPR target from patient MoveNet torso keypoints.
    static func chestTargetFromPatientMoveNetPose(
        _ pose: MoveNetPose,
        rescuer: FullBodySkeleton?
    ) -> PatientDetection? {
        let minScore: Float = 0.22
        let ls = pose.keypoint(.leftShoulder, minConfidence: minScore)
        let rs = pose.keypoint(.rightShoulder, minConfidence: minScore)
        let lh = pose.keypoint(.leftHip, minConfidence: minScore)
        let rh = pose.keypoint(.rightHip, minConfidence: minScore)

        let torsoCount = [ls, rs, lh, rh].compactMap { $0 }.count
        guard torsoCount >= 3 else { return nil }

        func vision(_ kp: MoveNetKeypoint) -> CGPoint {
            CGPoint(x: kp.x, y: 1.0 - kp.y)
        }

        var points: [CGPoint] = []
        if let ls { points.append(vision(ls)) }
        if let rs { points.append(vision(rs)) }
        if let lh { points.append(vision(lh)) }
        if let rh { points.append(vision(rh)) }
        guard points.count >= 3 else { return nil }

        let xs = points.map(\.x)
        let ys = points.map(\.y)
        var torsoBox = clamp(CGRect(
            x: xs.min() ?? 0,
            y: ys.min() ?? 0,
            width: (xs.max() ?? 1) - (xs.min() ?? 0),
            height: (ys.max() ?? 1) - (ys.min() ?? 0)
        ).insetBy(dx: -0.04, dy: -0.04))

        guard torsoBox.width > 0.06, torsoBox.height > 0.04 else { return nil }

        if let rescuer, let center = rescuer.centerPoint,
           torsoBox.insetBy(dx: -0.02, dy: -0.02).contains(center) {
            return nil
        }

        torsoBox = anchorChestBelowArms(torsoBox, rescuer: rescuer)

        let shoulderMid: CGPoint
        if let ls, let rs {
            shoulderMid = midpoint(vision(ls), vision(rs))
        } else if let ls {
            shoulderMid = vision(ls)
        } else if let rs {
            shoulderMid = vision(rs)
        } else {
            shoulderMid = CGPoint(x: torsoBox.midX, y: torsoBox.maxY - torsoBox.height * 0.15)
        }

        let hipMid: CGPoint
        if let lh, let rh {
            hipMid = midpoint(vision(lh), vision(rh))
        } else if let lh {
            hipMid = vision(lh)
        } else if let rh {
            hipMid = vision(rh)
        } else {
            hipMid = CGPoint(x: torsoBox.midX, y: torsoBox.minY + torsoBox.height * 0.15)
        }

        let sternum = sternumPoint(shoulderMid: shoulderMid, hipMid: hipMid, chestBox: torsoBox)
        let confidences = [ls, rs, lh, rh].compactMap { $0?.confidence }.map(Double.init)
        let avgConf = confidences.isEmpty ? 0.5 : confidences.reduce(0, +) / Double(confidences.count)

        return PatientDetection(
            boundingBox: torsoBox,
            sternumPoint: sternum,
            confidence: min(max(avgConf, 0.42), 0.96),
            label: "patient_label"
        )
    }

    /// Infer chest region under the rescuer only when kneeling CPR posture is visible.
    /// Box is anchored below the arms — not centered on moving wrists.
    static func chestTargetUnderHandsIfCPRPosture(
        rescuer: FullBodySkeleton
    ) -> PatientDetection? {
        guard
            let lw = rescuer.leftWrist,
            let rw = rescuer.rightWrist,
            let ls = rescuer.leftShoulder,
            let rs = rescuer.rightShoulder
        else {
            return nil
        }

        let wristMid = midpoint(lw, rw)
        let shoulderMid = midpoint(ls, rs)
        let shoulderWidth = max(hypot(ls.x - rs.x, ls.y - rs.y), 0.18)
        let wristGap = hypot(lw.x - rw.x, lw.y - rw.y)
        let handsTogether = wristGap < shoulderWidth * 0.80
        let handsAwayFromShoulders = hypot(wristMid.x - shoulderMid.x, wristMid.y - shoulderMid.y) > shoulderWidth * 0.45

        guard handsTogether, handsAwayFromShoulders else { return nil }

        let wristLine = min(lw.y, rw.y)
        let width = min(max(shoulderWidth * 1.05, 0.22), 0.46)
        let height = min(max(width * 0.58, 0.14), 0.30)
        let topY = wristLine - 0.015
        let bottomY = topY - height

        guard bottomY >= 0.02 else { return nil }

        let chestBox = clamp(CGRect(
            x: wristMid.x - width / 2,
            y: bottomY,
            width: width,
            height: height
        ))

        let sternum = CGPoint(
            x: chestBox.midX,
            y: chestBox.minY + chestBox.height * 0.58
        )

        return PatientDetection(
            boundingBox: chestBox,
            sternumPoint: clamp(sternum),
            confidence: min(max(rescuer.cprArmConfidence, 0.45), 0.90),
            label: "patient_label"
        )
    }

    // MARK: - Geometry helpers

    /// Shift the chest box down so it sits on the patient under the rescuer's arms.
    private static func anchorChestBelowArms(_ chestBox: CGRect, rescuer: FullBodySkeleton?) -> CGRect {
        guard let rescuer, let wristLine = BelowWristPatientGate.wristLineY(from: rescuer) else {
            return chestBox
        }

        let margin: CGFloat = 0.018
        let maxTop = wristLine - margin
        guard chestBox.maxY > maxTop else { return chestBox }

        var shifted = chestBox
        shifted.origin.y -= (chestBox.maxY - maxTop)
        return clamp(shifted)
    }

    private static func sternumPoint(
        shoulderMid: CGPoint,
        hipMid: CGPoint,
        chestBox: CGRect
    ) -> CGPoint {
        let anatomical = CGPoint(
            x: shoulderMid.x + (hipMid.x - shoulderMid.x) * 0.35,
            y: shoulderMid.y + (hipMid.y - shoulderMid.y) * 0.35
        )
        let centered = CGPoint(
            x: chestBox.midX,
            y: chestBox.minY + chestBox.height * 0.56
        )
        return clamp(CGPoint(
            x: anatomical.x * 0.35 + centered.x * 0.65,
            y: anatomical.y * 0.35 + centered.y * 0.65
        ))
    }

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    private static func patientBox(_ patient: FullBodySkeleton) -> CGRect {
        let points = patient.allPoints.map(\.1)
        let minX = points.map(\.x).min() ?? 0.35
        let maxX = points.map(\.x).max() ?? 0.65
        let minY = points.map(\.y).min() ?? 0.35
        let maxY = points.map(\.y).max() ?? 0.65
        return clamp(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
    }

    private static func clamp(_ rect: CGRect) -> CGRect {
        let x = max(0, min(rect.minX, 1))
        let y = max(0, min(rect.minY, 1))
        let w = max(0.001, min(rect.width, 1 - x))
        let h = max(0.001, min(rect.height, 1 - y))
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private static func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: max(0, min(point.x, 1)), y: max(0, min(point.y, 1)))
    }
}
