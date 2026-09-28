import CoreGraphics
import Foundation

/// Confidence gating + per-joint 1€ smoothing + rescuer lock that never drops blue nodes mid-session.
final class PoseTrackingFilter {
    private var jointFilters: [String: OneEuroPoint] = [:]
    private var lastJointValue: [String: CGPoint] = [:]
    private var lastJointSeen: [String: TimeInterval] = [:]

    private var lastGoodRescuer: FullBodySkeleton?
    private var lastGoodPatient: PatientDetection?
    private var lastRescuerSeen: TimeInterval = 0
    private var lastPatientSeen: TimeInterval = 0
    private var patientStableFrames = 0
    private var rescuerEverLocked = false
    private var patientEverLocked = false

    private var smoothedPatientBox: CGRect?
    private var smoothedSternum: CGPoint?

    private let minPatientStableFrames = 2
    private let patientGate = 0.10
    private let patientHold: TimeInterval = 1.5
    private let rescuerHold: TimeInterval = 0.35
    private let lockedJointHold: TimeInterval = 0.45

    private let jointMinCutoff = 1.2
    private let jointBeta = 0.7
    private let patientPositionAlpha = 0.35
    private let lockedPatientPositionAlpha = 0.06

    private static let jointPaths: [(String, WritableKeyPath<FullBodySkeleton, CGPoint?>)] = [
        ("nose", \.nose), ("neck", \.neck),
        ("leftShoulder", \.leftShoulder), ("rightShoulder", \.rightShoulder),
        ("leftElbow", \.leftElbow), ("rightElbow", \.rightElbow),
        ("leftWrist", \.leftWrist), ("rightWrist", \.rightWrist),
        ("leftHip", \.leftHip), ("rightHip", \.rightHip),
        ("leftKnee", \.leftKnee), ("rightKnee", \.rightKnee),
        ("leftAnkle", \.leftAnkle), ("rightAnkle", \.rightAnkle),
        ("root", \.root)
    ]

    func reset() {
        jointFilters.removeAll()
        lastJointValue.removeAll()
        lastJointSeen.removeAll()
        smoothedPatientBox = nil
        smoothedSternum = nil
        patientStableFrames = 0
        lastGoodRescuer = nil
        lastGoodPatient = nil
        lastRescuerSeen = 0
        lastPatientSeen = 0
        rescuerEverLocked = false
        patientEverLocked = false
    }

    func process(
        rawRescuer: FullBodySkeleton?,
        rawPatient: PatientDetection?,
        timestamp: TimeInterval
    ) -> (rescuer: FullBodySkeleton?, patient: PatientDetection?) {
        if let rawRescuer, hasDrawableRescuer(rawRescuer) {
            let smoothed = smoothSkeleton(rawRescuer, timestamp: timestamp, locked: rescuerEverLocked)
            lastGoodRescuer = mergeRescuer(lastGoodRescuer, smoothed)
            lastRescuerSeen = timestamp
            rescuerEverLocked = true
        } else if lastRescuerSeen > 0, timestamp - lastRescuerSeen > rescuerHold {
            clearRescuerTracking()
        }

        let gatedPatient = gatePatient(rawPatient, rescuer: lastGoodRescuer ?? rawRescuer)

        if let gatedPatient {
            lastGoodPatient = gatedPatient
            lastPatientSeen = timestamp
        }

        let rescuerOut = hold(lastGoodRescuer, lastSeen: lastRescuerSeen, now: timestamp, window: rescuerHold)
        let patientOut: PatientDetection?
        if let gatedPatient {
            patientOut = gatedPatient
        } else if patientEverLocked, let lastGoodPatient {
            patientOut = lastGoodPatient
        } else {
            patientOut = hold(lastGoodPatient, lastSeen: lastPatientSeen, now: timestamp, window: patientHold)
        }
        return (rescuerOut, patientOut)
    }

    private func clearRescuerTracking() {
        lastGoodRescuer = nil
        lastRescuerSeen = 0
        rescuerEverLocked = false
        jointFilters.removeAll()
        lastJointValue.removeAll()
        lastJointSeen.removeAll()
    }

    private func hasDrawableRescuer(_ skeleton: FullBodySkeleton) -> Bool {
        skeleton.isOverlayVisible
    }

    /// Keep the last good value for each joint when a new frame omits it.
    private func mergeRescuer(_ previous: FullBodySkeleton?, _ incoming: FullBodySkeleton) -> FullBodySkeleton {
        guard var previous else { return incoming }

        for (_, kp) in Self.jointPaths {
            if let value = incoming[keyPath: kp] {
                previous[keyPath: kp] = value
            }
        }
        previous.averageConfidence = max(previous.averageConfidence, incoming.averageConfidence)
        return previous
    }

    private func hold<T>(_ value: T?, lastSeen: TimeInterval, now: TimeInterval, window: TimeInterval) -> T? {
        guard value != nil, lastSeen > 0, now - lastSeen < window else { return nil }
        return value
    }

    private func smoothSkeleton(_ raw: FullBodySkeleton, timestamp t: Double, locked: Bool) -> FullBodySkeleton {
        let jointHold = locked ? lockedJointHold : 0.5
        var out = raw
        for (name, kp) in Self.jointPaths {
            if let rawP = raw[keyPath: kp] {
                var f = jointFilters[name] ?? OneEuroPoint(minCutoff: jointMinCutoff, beta: jointBeta)
                let fp = f.filter(rawP, timestamp: t)
                jointFilters[name] = f
                lastJointValue[name] = fp
                lastJointSeen[name] = t
                out[keyPath: kp] = fp
            } else if let last = lastJointValue[name], let seen = lastJointSeen[name], t - seen < jointHold {
                out[keyPath: kp] = last
            } else {
                out[keyPath: kp] = nil
            }
        }
        return out
    }

    private func gatePatient(_ raw: PatientDetection?, rescuer: FullBodySkeleton?) -> PatientDetection? {
        let minConfidence = patientEverLocked ? 0.06 : patientGate
        guard let raw, raw.confidence >= minConfidence else {
            if !patientEverLocked {
                patientStableFrames = max(0, patientStableFrames - 1)
            }
            return nil
        }

        if !patientEverLocked,
           let rescuer,
           !BelowWristPatientGate.isPatientBelowWrists(patient: raw, rescuer: rescuer) {
            patientStableFrames = max(0, patientStableFrames - 1)
            return nil
        }

        patientStableFrames += 1
        let box = smoothRect(raw.boundingBox, previous: smoothedPatientBox)
        let sternum = smoothPoint(raw.sternumPoint, previous: smoothedSternum)
        smoothedPatientBox = box
        smoothedSternum = sternum

        guard patientStableFrames >= minPatientStableFrames || patientEverLocked else { return nil }

        patientEverLocked = true
        return PatientDetection(
            boundingBox: box,
            sternumPoint: sternum,
            confidence: raw.confidence,
            label: raw.label
        )
    }

    private func smoothRect(_ raw: CGRect, previous: CGRect?) -> CGRect {
        guard let previous else { return raw }
        let a = patientEverLocked ? lockedPatientPositionAlpha : patientPositionAlpha
        return CGRect(
            x: raw.origin.x * a + previous.origin.x * (1 - a),
            y: raw.origin.y * a + previous.origin.y * (1 - a),
            width: raw.width * a + previous.width * (1 - a),
            height: raw.height * a + previous.height * (1 - a)
        )
    }

    private func smoothPoint(_ raw: CGPoint, previous: CGPoint?) -> CGPoint {
        guard let previous else { return raw }
        if patientEverLocked { return previous }
        let a = patientPositionAlpha
        return CGPoint(
            x: raw.x * a + previous.x * (1 - a),
            y: raw.y * a + previous.y * (1 - a)
        )
    }
}

extension FullBodySkeleton {
    var cprArmConfidence: Double {
        let joints: [CGPoint?] = [leftWrist, rightWrist, leftElbow, rightElbow, leftShoulder, rightShoulder]
        let present = joints.compactMap { $0 }.count
        switch present {
        case 4...: return averageConfidence
        case 3: return averageConfidence * 0.85
        case 2: return averageConfidence * 0.7
        default: return averageConfidence * 0.45
        }
    }

    var centerPoint: CGPoint? {
        let pts = [leftShoulder, rightShoulder, leftHip, rightHip].compactMap { $0 }
        guard !pts.isEmpty else { return nil }
        let x = pts.map(\.x).reduce(0, +) / CGFloat(pts.count)
        let y = pts.map(\.y).reduce(0, +) / CGFloat(pts.count)
        return CGPoint(x: x, y: y)
    }
}

private struct OneEuroScalar {
    let minCutoff: Double
    let beta: Double
    var xPrev: Double?
    var dxPrev: Double?
    var tPrev: Double?

    mutating func filter(_ x: Double, timestamp t: Double) -> Double {
        guard let xPrev, let tPrev else {
            self.xPrev = x
            self.tPrev = t
            return x
        }

        let dt = max(t - tPrev, 1.0 / 120.0)
        let dx = (x - xPrev) / dt
        let edx = dxPrev.map { 0.5 * dx + 0.5 * $0 } ?? dx
        dxPrev = edx

        let cutoff = minCutoff + beta * abs(edx)
        let tau = 1.0 / (2.0 * Double.pi * cutoff)
        let alpha = 1.0 / (1.0 + tau / dt)
        let filtered = alpha * x + (1 - alpha) * xPrev

        self.xPrev = filtered
        self.tPrev = t
        return filtered
    }
}

private struct OneEuroPoint {
    let minCutoff: Double
    let beta: Double
    private var xFilter: OneEuroScalar
    private var yFilter: OneEuroScalar

    init(minCutoff: Double, beta: Double) {
        self.minCutoff = minCutoff
        self.beta = beta
        xFilter = OneEuroScalar(minCutoff: minCutoff, beta: beta)
        yFilter = OneEuroScalar(minCutoff: minCutoff, beta: beta)
    }

    mutating func filter(_ point: CGPoint, timestamp t: Double) -> CGPoint {
        CGPoint(
            x: xFilter.filter(Double(point.x), timestamp: t),
            y: yFilter.filter(Double(point.y), timestamp: t)
        )
    }
}
