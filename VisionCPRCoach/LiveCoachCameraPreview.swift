import SwiftUI
import AVFoundation
import ARKit

/// Unified live camera surface: AVCapture on standard iPhones, ARKit camera on LiDAR devices.
struct LiveCoachCameraPreview: View {
    let captureSession: AVCaptureSession
    var arSession: ARSession?
    var usesARPipeline: Bool = false
    var rescuer: FullBodySkeleton? = nil
    var patient: PatientDetection? = nil
    var showOverlay: Bool = true
    var frameWidth: Int = 0
    var frameHeight: Int = 0
    var onViewportSizeChange: ((CGSize) -> Void)? = nil

    var body: some View {
        Group {
            if usesARPipeline, let arSession {
                ARCameraPreview(
                    session: arSession,
                    rescuer: rescuer,
                    patient: patient,
                    showOverlay: showOverlay,
                    frameWidth: frameWidth,
                    frameHeight: frameHeight,
                    onViewportSizeChange: onViewportSizeChange
                )
            } else {
                CameraPreview(
                    session: captureSession,
                    rescuer: rescuer,
                    patient: patient,
                    showOverlay: showOverlay,
                    frameWidth: frameWidth,
                    frameHeight: frameHeight,
                    onViewportSizeChange: onViewportSizeChange
                )
            }
        }
    }
}
