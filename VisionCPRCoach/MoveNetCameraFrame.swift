import CoreImage
import CoreMedia
import CoreVideo

/// Rotates the back-camera sample buffer to portrait-up (same space as Vision `.right`).
enum MoveNetCameraFrame {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    static func makePortraitBuffer(from sampleBuffer: CMSampleBuffer) -> CVPixelBuffer? {
        guard let src = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        return makePortraitBuffer(from: src)
    }

    static func makePortraitBuffer(from src: CVPixelBuffer) -> CVPixelBuffer? {
        var oriented = CIImage(cvPixelBuffer: src).oriented(.right)
        let extent = oriented.extent
        // CIImage rotation leaves a negative origin — render would crop/shift without this fix.
        if extent.origin.x != 0 || extent.origin.y != 0 {
            oriented = oriented.transformed(
                by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y)
            )
        }

        let width = Int(oriented.extent.width.rounded())
        let height = Int(oriented.extent.height.rounded())
        guard width > 0, height > 0 else { return nil }

        var dst: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &dst
        )
        guard status == kCVReturnSuccess, let dst else { return nil }

        ciContext.render(oriented, to: dst)
        return dst
    }
}
