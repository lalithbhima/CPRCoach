import ARKit
import Foundation

/// Runs ARKit world tracking with scene depth on LiDAR-capable devices.
final class LiDARDepthSession: NSObject {
    static var isSupported: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    let session = ARSession()
    private let queue = DispatchQueue(label: "lidar.depth.session", qos: .userInteractive)

    var onFrame: ((ARFrame) -> Void)?

    private(set) var isRunning = false

    func start() {
        guard Self.isSupported else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal]

            if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
                configuration.frameSemantics.insert(.smoothedSceneDepth)
            }
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                configuration.frameSemantics.insert(.sceneDepth)
            }
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                configuration.sceneReconstruction = .mesh
            }

            self.session.delegate = self
            self.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            self.isRunning = true
        }
    }

    func pause() {
        queue.async { [weak self] in
            self?.session.pause()
            self?.isRunning = false
        }
    }
}

extension LiDARDepthSession: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        onFrame?(frame)
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        print("LiDAR ARSession error: \(error.localizedDescription)")
    }
}
