import Foundation
import CoreVideo
import CoreImage

struct MoveNetCropper {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Crop the same portrait buffer MoveNet uses so keypoints map back correctly.
    static func cropPortraitBuffer(
        _ pixelBuffer: CVPixelBuffer,
        visionRect: CGRect
    ) -> CVPixelBuffer? {
        guard let portrait = MoveNetCameraFrame.makePortraitBuffer(from: pixelBuffer) else {
            return nil
        }

        let width = CGFloat(CVPixelBufferGetWidth(portrait))
        let height = CGFloat(CVPixelBufferGetHeight(portrait))

        // Vision rect is bottom-left normalized in portrait space.
        let crop = CGRect(
            x: visionRect.minX * width,
            y: visionRect.minY * height,
            width: visionRect.width * width,
            height: visionRect.height * height
        ).standardized.intersection(CGRect(x: 0, y: 0, width: width, height: height))

        guard !crop.isNull, crop.width > 10, crop.height > 10 else {
            return nil
        }

        let ciImage = CIImage(cvPixelBuffer: portrait)
        let cropped = ciImage.cropped(to: crop)

        var output: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
        ]

        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(crop.width),
            Int(crop.height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &output
        )

        guard let output else { return nil }

        context.render(
            cropped.transformed(by: CGAffineTransform(
                translationX: -crop.origin.x,
                y: -crop.origin.y
            )),
            to: output
        )

        return output
    }
}
