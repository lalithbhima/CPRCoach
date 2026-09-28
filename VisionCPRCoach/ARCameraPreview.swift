import ARKit
import SwiftUI

/// Camera preview driven by ARSession (LiDAR pipeline). Shows the live AR camera feed + pose overlay.
struct ARCameraPreview: UIViewRepresentable {
    let session: ARSession
    var rescuer: FullBodySkeleton? = nil
    var patient: PatientDetection? = nil
    var showOverlay: Bool = true
    var frameWidth: Int = 0
    var frameHeight: Int = 0
    var onViewportSizeChange: ((CGSize) -> Void)? = nil

    func makeUIView(context: Context) -> ARCameraPreviewContainer {
        let container = ARCameraPreviewContainer()
        container.arView.session = session
        container.arView.automaticallyUpdatesLighting = false

        container.overlayView.rescuer = rescuer
        container.overlayView.patient = patient
        container.overlayView.frameWidth = frameWidth
        container.overlayView.frameHeight = frameHeight
        container.overlayView.isHidden = !showOverlay
        container.onViewportSizeChange = onViewportSizeChange
        return container
    }

    func updateUIView(_ uiView: ARCameraPreviewContainer, context: Context) {
        if uiView.arView.session !== session {
            uiView.arView.session = session
        }
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

final class ARCameraPreviewContainer: UIView {
    let arView = ARSCNView(frame: .zero)
    let overlayView = CameraPoseOverlayView()
    var onViewportSizeChange: ((CGSize) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(arView)
        addSubview(overlayView)
        overlayView.backgroundColor = .clear
        overlayView.isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        arView.frame = bounds
        overlayView.frame = bounds
        reportViewportSize()
    }

    func reportViewportSize() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        onViewportSizeChange?(bounds.size)
    }
}
