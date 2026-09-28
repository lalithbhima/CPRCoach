import Foundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Vision

final class DualMoveNetSceneAnalyzer {
    private let rescuerMoveNet = MoveNetPoseEstimator()
    private let patientMoveNet = MoveNetPoseEstimator()

    private let humanRectRequest: VNDetectHumanRectanglesRequest = {
        let request = VNDetectHumanRectanglesRequest()
        return request
    }()

    func analyze(
        sampleBuffer: CMSampleBuffer,
        completion: @escaping (_ rescuerPose: MoveNetPose?, _ patientTarget: PatientCPRTarget?) -> Void
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            completion(nil, nil)
            return
        }

        guard rescuerMoveNet.isModelLoaded else {
            completion(nil, nil)
            return
        }

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .right,
            options: [:]
        )

        do {
            try handler.perform([humanRectRequest])
        } catch {
            completion(nil, nil)
            return
        }

        let rects = humanRectRequest.results ?? []

        let portrait = MoveNetCameraFrame.makePortraitBuffer(from: pixelBuffer)
        let frameWidth = portrait.map { CVPixelBufferGetWidth($0) } ?? CVPixelBufferGetWidth(pixelBuffer)
        let frameHeight = portrait.map { CVPixelBufferGetHeight($0) } ?? CVPixelBufferGetHeight(pixelBuffer)

        var rescuerPose: MoveNetPose?
        var patientTarget: PatientCPRTarget?
        var rescuerSkeleton: FullBodySkeleton?

        let rescuerRect = findRescuerRect(rects, excluding: nil)

        if let rescuerRect,
           let rescuerCrop = MoveNetCropper.cropPortraitBuffer(pixelBuffer, visionRect: rescuerRect) {
            if let cropPose = try? rescuerMoveNet.estimatePose(fromPortrait: rescuerCrop) {
                rescuerPose = mapPoseToFullFrame(
                    cropPose,
                    cropRect: rescuerRect,
                    frameWidth: frameWidth,
                    frameHeight: frameHeight
                )
                rescuerSkeleton = rescuerPose?.toFullBodySkeleton()
            }
        }

        let patientRect = findHorizontalPatientRect(
            rects,
            below: rescuerSkeleton
        )

        if let patientRect,
           let patientCrop = MoveNetCropper.cropPortraitBuffer(pixelBuffer, visionRect: patientRect) {
            if let patientPose = try? patientMoveNet.estimatePatientCropPose(fromPortrait: patientCrop),
               let built = buildPatientTarget(from: patientPose, cropRect: patientRect),
               let rescuerSkeleton,
               BelowWristPatientGate.isTargetBelowWrists(built, rescuer: rescuerSkeleton) {
                patientTarget = built
            }
        }

        completion(rescuerPose, patientTarget)
    }

    private func findHorizontalPatientRect(
        _ rects: [VNHumanObservation],
        below rescuer: FullBodySkeleton?
    ) -> CGRect? {
        let candidates = rects
            .map(\.boundingBox)
            .filter { box in
                let horizontal = box.width > box.height * 1.15
                let bigEnough = box.width * box.height > 0.025
                guard horizontal && bigEnough else { return false }
                guard let rescuer else { return true }
                return BelowWristPatientGate.isRectBelowWrists(box, rescuer: rescuer)
            }

        return candidates.max { a, b in
            scorePatientBox(a) < scorePatientBox(b)
        }
    }

    private func findRescuerRect(
        _ rects: [VNHumanObservation],
        excluding patientRect: CGRect?
    ) -> CGRect? {
        let candidates = rects.map(\.boundingBox).filter { box in
            guard let patientRect else { return true }
            return box.intersection(patientRect).isNull
        }

        return candidates.max { a, b in
            a.height < b.height
        }
    }

    private func scorePatientBox(_ box: CGRect) -> Double {
        let horizontalRatio = Double(box.width / max(box.height, 0.001))
        let area = Double(box.width * box.height)
        return horizontalRatio * 2.0 + area * 8.0
    }

    private func buildPatientTarget(
        from pose: MoveNetPose,
        cropRect: CGRect
    ) -> PatientCPRTarget? {
        guard
            let ls = pose.keypoint(.leftShoulder),
            let rs = pose.keypoint(.rightShoulder),
            let lh = pose.keypoint(.leftHip),
            let rh = pose.keypoint(.rightHip),
            ls.confidence > 0.20,
            rs.confidence > 0.20,
            lh.confidence > 0.15,
            rh.confidence > 0.15
        else {
            return nil
        }

        let leftShoulder = topLeftToVision(cropPointToFullFrame(ls.cgPoint, cropRect: cropRect))
        let rightShoulder = topLeftToVision(cropPointToFullFrame(rs.cgPoint, cropRect: cropRect))
        let leftHip = topLeftToVision(cropPointToFullFrame(lh.cgPoint, cropRect: cropRect))
        let rightHip = topLeftToVision(cropPointToFullFrame(rh.cgPoint, cropRect: cropRect))

        let confidence = Double(
            (ls.confidence + rs.confidence + lh.confidence + rh.confidence) / 4
        )

        return PatientCPRTargetBuilder.build(
            leftShoulder: leftShoulder,
            rightShoulder: rightShoulder,
            leftHip: leftHip,
            rightHip: rightHip,
            confidence: confidence
        )
    }

    /// MoveNet crop-local (top-left) → full-frame top-left normalized.
    private func cropPointToFullFrame(_ point: CGPoint, cropRect: CGRect) -> CGPoint {
        let crop = visionRectToTopLeft(cropRect)
        return CGPoint(
            x: crop.minX + point.x * crop.width,
            y: crop.minY + point.y * crop.height
        )
    }

    private func visionRectToTopLeft(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: 1.0 - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func topLeftToVision(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: 1.0 - point.y)
    }

    /// Remap crop-local keypoints to full portrait MoveNet space (top-left).
    private func mapPoseToFullFrame(
        _ pose: MoveNetPose,
        cropRect: CGRect,
        frameWidth: Int,
        frameHeight: Int
    ) -> MoveNetPose {
        let mapped = pose.keypoints.map { kp -> MoveNetKeypoint in
            let full = cropPointToFullFrame(kp.cgPoint, cropRect: cropRect)
            return MoveNetKeypoint(
                joint: kp.joint,
                x: full.x,
                y: full.y,
                confidence: kp.confidence
            )
        }
        return MoveNetPose(
            keypoints: mapped,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            inferenceMs: pose.inferenceMs
        )
    }
}

private extension MoveNetKeypoint {
    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}
