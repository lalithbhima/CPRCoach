import CoreGraphics

/// Ensures the patient chest target sits on the body below the rescuer's wrists (Vision space, origin bottom-left).
enum BelowWristPatientGate {

    /// Wrist midpoint in Vision coordinates.
    static func wristMid(from rescuer: FullBodySkeleton) -> CGPoint? {
        guard let lw = rescuer.leftWrist, let rw = rescuer.rightWrist else { return nil }
        return CGPoint(x: (lw.x + rw.x) / 2, y: (lw.y + rw.y) / 2)
    }

    /// Lowest wrist Y in Vision space (smaller Y = lower on screen).
    static func wristLineY(from rescuer: FullBodySkeleton) -> CGFloat? {
        guard let lw = rescuer.leftWrist, let rw = rescuer.rightWrist else { return nil }
        return min(lw.y, rw.y)
    }

    /// Patient sternum / chest must sit below both wrists.
    static func isPatientBelowWrists(
        patient: PatientDetection,
        rescuer: FullBodySkeleton,
        margin: CGFloat = 0.012
    ) -> Bool {
        guard let wristMid = wristMid(from: rescuer) else { return false }

        let chestTop = patient.boundingBox.maxY
        let sternum = patient.sternumPoint

        let belowWristMid = sternum.y < wristMid.y - margin
        let chestTopAtOrBelowWrists = chestTop <= wristMid.y + margin

        return belowWristMid && chestTopAtOrBelowWrists
    }

    static func isRectBelowWrists(
        _ box: CGRect,
        rescuer: FullBodySkeleton,
        margin: CGFloat = 0.015
    ) -> Bool {
        guard let wristLine = wristLineY(from: rescuer) else { return false }
        // Body on the ground: rect top (maxY) at or below the wrist line.
        return box.maxY <= wristLine + margin && box.midY < wristLine - margin * 0.5
    }

    static func isTargetBelowWrists(
        _ target: PatientCPRTarget,
        rescuer: FullBodySkeleton,
        margin: CGFloat = 0.012
    ) -> Bool {
        let detection = PatientDetection(target: target)
        return isPatientBelowWrists(patient: detection, rescuer: rescuer, margin: margin)
    }

    /// Returns the patient only when its chest is on the body below the rescuer wrists.
    static func filter(
        _ patient: PatientDetection?,
        rescuer: FullBodySkeleton?
    ) -> PatientDetection? {
        guard let patient, let rescuer else { return nil }
        return isPatientBelowWrists(patient: patient, rescuer: rescuer) ? patient : nil
    }

    static func filter(
        _ target: PatientCPRTarget?,
        rescuer: FullBodySkeleton?
    ) -> PatientCPRTarget? {
        guard let target, let rescuer else { return nil }
        return isTargetBelowWrists(target, rescuer: rescuer) ? target : nil
    }
}
