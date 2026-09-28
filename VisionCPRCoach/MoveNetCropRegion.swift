import CoreGraphics
import Foundation

/// Crop region exactly as `init_crop_region` / `determine_crop_region` in
/// https://www.tensorflow.org/hub/tutorials/movenet
struct MoveNetCropRegion: Equatable {
    var yMin: CGFloat
    var xMin: CGFloat
    var yMax: CGFloat
    var xMax: CGFloat
    var height: CGFloat
    var width: CGFloat

    var rect: CGRect {
        CGRect(x: xMin, y: yMin, width: width, height: height)
    }

    /// Tutorial: `init_crop_region(image_height, image_width)`
    static func initial(imageHeight: Int, imageWidth: Int) -> MoveNetCropRegion {
        let h = CGFloat(imageHeight)
        let w = CGFloat(imageWidth)

        let boxHeight: CGFloat
        let boxWidth: CGFloat
        let yMin: CGFloat
        let xMin: CGFloat

        if w > h {
            boxHeight = w / h
            boxWidth = 1.0
            yMin = (h / 2 - w / 2) / h
            xMin = 0.0
        } else {
            boxHeight = 1.0
            boxWidth = h / w
            yMin = 0.0
            xMin = (w / 2 - h / 2) / w
        }

        return MoveNetCropRegion(
            yMin: yMin,
            xMin: xMin,
            yMax: yMin + boxHeight,
            xMax: xMin + boxWidth,
            height: boxHeight,
            width: boxWidth
        )
    }

    /// Vision human-rect (bottom-left origin) → MoveNet crop (top-left normalized).
    static func fromVisionRect(_ rect: CGRect, padding: CGFloat = 0.12) -> MoveNetCropRegion {
        let standardized = rect.standardized
        let padW = standardized.width * padding
        let padH = standardized.height * padding

        let xMin = max(0, standardized.minX - padW)
        let visionMaxY = standardized.maxY + padH
        let visionMinY = standardized.minY - padH
        let yMinTL = max(0, 1.0 - visionMaxY)
        let yMaxTL = min(1, 1.0 - visionMinY)
        let xMax = min(1, standardized.maxX + padW)

        return MoveNetCropRegion(
            yMin: yMinTL,
            xMin: xMin,
            yMax: yMaxTL,
            xMax: xMax,
            height: yMaxTL - yMinTL,
            width: xMax - xMin
        )
    }
}

/// [1, 1, 17, 3] tensor — each joint is (y, x, score) normalized to full image after `run_inference`.
struct MoveNetKeypointsTensor {
    private(set) var values: [Float]

    init(rawCropOutput: [Float32]) {
        values = rawCropOutput.map { Float($0) }
    }

    subscript(joint: MoveNetJoint) -> (y: Float, x: Float, score: Float) {
        let base = joint.rawValue * 3
        return (values[base], values[base + 1], values[base + 2])
    }

    mutating func set(joint: MoveNetJoint, y: Float, x: Float, score: Float) {
        let base = joint.rawValue * 3
        values[base] = y
        values[base + 1] = x
        values[base + 2] = score
    }

    /// Tutorial: `run_inference` — map crop-normalized keypoints back to full-image normalized coords.
    mutating func mapToFullImage(crop: MoveNetCropRegion) {
        for joint in MoveNetJoint.allCases {
            var (y, x, score) = self[joint]
            y = Float(crop.yMin) + Float(crop.height) * y
            x = Float(crop.xMin) + Float(crop.width) * x
            set(joint: joint, y: y, x: x, score: score)
        }
    }

    /// Tutorial: `determine_crop_region(keypoints, image_height, image_width)`
    static func determineCropRegion(
        from tensor: MoveNetKeypointsTensor,
        imageHeight: Int,
        imageWidth: Int,
        minScore: Float = 0.2
    ) -> MoveNetCropRegion {
        let h = CGFloat(imageHeight)
        let w = CGFloat(imageWidth)

        func yPx(_ j: MoveNetJoint) -> CGFloat { CGFloat(tensor[j].y) * h }
        func xPx(_ j: MoveNetJoint) -> CGFloat { CGFloat(tensor[j].x) * w }
        func score(_ j: MoveNetJoint) -> Float { tensor[j].score }

        let torsoOk =
            (score(.leftHip) > minScore || score(.rightHip) > minScore) &&
            (score(.leftShoulder) > minScore || score(.rightShoulder) > minScore)

        guard torsoOk else {
            return .initial(imageHeight: imageHeight, imageWidth: imageWidth)
        }

        let centerY = (yPx(.leftHip) + yPx(.rightHip)) / 2
        let centerX = (xPx(.leftHip) + xPx(.rightHip)) / 2

        let torsoJoints: [MoveNetJoint] = [.leftShoulder, .rightShoulder, .leftHip, .rightHip]
        var maxTorsoYRange: CGFloat = 0
        var maxTorsoXRange: CGFloat = 0
        for j in torsoJoints {
            maxTorsoYRange = max(maxTorsoYRange, abs(centerY - yPx(j)))
            maxTorsoXRange = max(maxTorsoXRange, abs(centerX - xPx(j)))
        }

        var maxBodyYRange = maxTorsoYRange
        var maxBodyXRange = maxTorsoXRange
        for j in MoveNetJoint.allCases where tensor[j].score >= minScore {
            maxBodyYRange = max(maxBodyYRange, abs(centerY - yPx(j)))
            maxBodyXRange = max(maxBodyXRange, abs(centerX - xPx(j)))
        }

        var cropLengthHalf = max(
            maxTorsoXRange * 1.9,
            maxTorsoYRange * 1.9,
            maxBodyYRange * 1.2,
            maxBodyXRange * 1.2
        )
        cropLengthHalf = min(cropLengthHalf, min(centerX, w - centerX, centerY, h - centerY))

        if cropLengthHalf > max(w, h) / 2 {
            return .initial(imageHeight: imageHeight, imageWidth: imageWidth)
        }

        let cropLength = cropLengthHalf * 2
        let cropCornerY = centerY - cropLengthHalf
        let cropCornerX = centerX - cropLengthHalf

        let yMin = cropCornerY / h
        let xMin = cropCornerX / w
        let yMax = (cropCornerY + cropLength) / h
        let xMax = (cropCornerX + cropLength) / w

        return MoveNetCropRegion(
            yMin: yMin,
            xMin: xMin,
            yMax: yMax,
            xMax: xMax,
            height: yMax - yMin,
            width: xMax - xMin
        )
    }
}
