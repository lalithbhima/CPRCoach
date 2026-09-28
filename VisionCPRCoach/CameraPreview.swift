import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var rescuer: FullBodySkeleton? = nil
    var patient: PatientDetection? = nil
    var showOverlay: Bool = true
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill
    var frameWidth: Int = 0
    var frameHeight: Int = 0
    var onViewportSizeChange: ((CGSize) -> Void)? = nil

    func makeUIView(context: Context) -> CameraPreviewContainer {
        let container = CameraPreviewContainer()
        container.previewView.videoPreviewLayer.session = session
        container.previewView.videoPreviewLayer.videoGravity = videoGravity

        container.overlayView.isFrontCamera = false
        container.overlayView.rescuer = rescuer
        container.overlayView.patient = patient
        container.overlayView.frameWidth = frameWidth
        container.overlayView.frameHeight = frameHeight
        container.overlayView.isHidden = !showOverlay
        container.onViewportSizeChange = onViewportSizeChange

        return container
    }

    func updateUIView(_ uiView: CameraPreviewContainer, context: Context) {
        uiView.previewView.videoPreviewLayer.videoGravity = videoGravity

        uiView.overlayView.isFrontCamera = false
        uiView.overlayView.rescuer = rescuer
        uiView.overlayView.patient = patient
        uiView.overlayView.frameWidth = frameWidth
        uiView.overlayView.frameHeight = frameHeight
        uiView.overlayView.isHidden = !showOverlay
        uiView.overlayView.setNeedsDisplay()
        uiView.onViewportSizeChange = onViewportSizeChange
        uiView.reportViewportSize()
    }
}

final class CameraPreviewContainer: UIView {
    let previewView = VideoPreviewView()
    let overlayView = CameraPoseOverlayView()
    var onViewportSizeChange: ((CGSize) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        addSubview(previewView)
        addSubview(overlayView)
        overlayView.backgroundColor = .clear
        overlayView.isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewView.frame = bounds
        overlayView.frame = bounds
        reportViewportSize()
    }

    func reportViewportSize() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        onViewportSizeChange?(bounds.size)
    }
}

final class VideoPreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

final class CameraPoseOverlayView: UIView {
    var rescuer: FullBodySkeleton? {
        didSet {
            if rescuer == nil {
                smoothedPoints.removeAll()
            }
        }
    }

    var patient: PatientDetection?

    var frameWidth: Int = 0
    var frameHeight: Int = 0
    var isFrontCamera: Bool = false

    private static let blue = UIColor(red: 0.29, green: 0.51, blue: 0.82, alpha: 1)
    private static let green = UIColor(red: 0.55, green: 0.95, blue: 0.20, alpha: 1.0)

    private var smoothedPoints: [String: CGPoint] = [:]
    private let smoothingAlpha: CGFloat = 0.45

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let videoRect = videoMappingRect(in: bounds)

        if let patient, let box = mappedPatientBox(videoRect: videoRect) {
            drawPatientBox(ctx: ctx, box: box)
        }

        if let rescuer, rescuer.isOverlayVisible {
            drawRescuerSkeleton(ctx: ctx, skeleton: rescuer, videoRect: videoRect)
        }
    }

    /// Connected skeleton: shoulders, elbows, wrists, hips (matches live_movenet_cpr.py EDGES).
    private func drawRescuerSkeleton(
        ctx: CGContext,
        skeleton: FullBodySkeleton,
        videoRect: CGRect
    ) {
        let ls = mappedPoint(skeleton.leftShoulder, videoRect: videoRect, key: "ls")
        let rs = mappedPoint(skeleton.rightShoulder, videoRect: videoRect, key: "rs")
        let le = mappedPoint(skeleton.leftElbow, videoRect: videoRect, key: "le")
        let re = mappedPoint(skeleton.rightElbow, videoRect: videoRect, key: "re")
        let lw = mappedPoint(skeleton.leftWrist, videoRect: videoRect, key: "lw")
        let rw = mappedPoint(skeleton.rightWrist, videoRect: videoRect, key: "rw")
        let lh = mappedPoint(skeleton.leftHip, videoRect: videoRect, key: "lh")
        let rh = mappedPoint(skeleton.rightHip, videoRect: videoRect, key: "rh")

        ctx.setLineWidth(4)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(Self.blue.cgColor)

        stroke(ctx, ls, rs)
        stroke(ctx, ls, le)
        stroke(ctx, le, lw)
        stroke(ctx, rs, re)
        stroke(ctx, re, rw)
        stroke(ctx, ls, lh)
        stroke(ctx, rs, rh)
        stroke(ctx, lh, rh)

        for point in [ls, rs, le, re, lw, rw, lh, rh].compactMap({ $0 }) {
            drawDot(ctx, at: point)
        }
    }

    private func mappedPoint(_ point: CGPoint?, videoRect: CGRect, key: String) -> CGPoint? {
        guard let point else { return nil }
        return mapVisionPoint(point, videoRect: videoRect, key: key)
    }

    private func drawDot(_ ctx: CGContext, at point: CGPoint) {
        let dot = CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)
        ctx.setFillColor(Self.blue.cgColor)
        ctx.fillEllipse(in: dot)
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: dot)
    }

    private func stroke(_ ctx: CGContext, _ a: CGPoint?, _ b: CGPoint?) {
        guard let a, let b else { return }
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
    }

    private func mappedPatientBox(videoRect: CGRect) -> CGRect? {
        guard let patient else { return nil }
        let box = visionRectToTopLeft(patient.boundingBox)
        return CGRect(
            x: videoRect.minX + box.minX * videoRect.width,
            y: videoRect.minY + box.minY * videoRect.height,
            width: box.width * videoRect.width,
            height: box.height * videoRect.height
        )
    }

    private func drawPatientBox(ctx: CGContext, box: CGRect) {
        ctx.setStrokeColor(Self.green.cgColor)
        ctx.setLineWidth(3)
        ctx.stroke(box)
    }

    private func videoMappingRect(in viewBounds: CGRect) -> CGRect {
        let w = CGFloat(frameWidth)
        let h = CGFloat(frameHeight)
        if w > 0, h > 0 {
            return aspectFillRect(
                imageWidth: w,
                imageHeight: h,
                container: viewBounds
            )
        }
        return viewBounds
    }

    private func mapVisionPoint(_ point: CGPoint, videoRect: CGRect, key: String) -> CGPoint {
        let topLeft = visionPointToTopLeft(point)
        let raw = CGPoint(
            x: videoRect.minX + topLeft.x * videoRect.width,
            y: videoRect.minY + topLeft.y * videoRect.height
        )
        return smooth(key: key, newPoint: raw)
    }

    private func visionPointToTopLeft(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: 1.0 - point.y)
    }

    private func visionRectToTopLeft(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: 1.0 - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func aspectFillRect(
        imageWidth: CGFloat,
        imageHeight: CGFloat,
        container: CGRect
    ) -> CGRect {
        guard imageWidth > 0, imageHeight > 0 else {
            return container
        }

        let imageAspect = imageWidth / imageHeight
        let containerAspect = container.width / container.height

        if imageAspect > containerAspect {
            let height = container.height
            let width = height * imageAspect
            let x = container.midX - width / 2
            return CGRect(x: x, y: container.minY, width: width, height: height)
        } else {
            let width = container.width
            let height = width / imageAspect
            let y = container.midY - height / 2
            return CGRect(x: container.minX, y: y, width: width, height: height)
        }
    }

    private func smooth(key: String, newPoint: CGPoint) -> CGPoint {
        guard let oldPoint = smoothedPoints[key] else {
            smoothedPoints[key] = newPoint
            return newPoint
        }

        let smoothed = CGPoint(
            x: oldPoint.x * (1 - smoothingAlpha) + newPoint.x * smoothingAlpha,
            y: oldPoint.y * (1 - smoothingAlpha) + newPoint.y * smoothingAlpha
        )
        smoothedPoints[key] = smoothed
        return smoothed
    }
}
