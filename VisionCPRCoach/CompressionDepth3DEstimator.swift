import ARKit
import CoreGraphics
import CoreVideo
import Foundation
import simd

final class CompressionDepth3DEstimator {
    private var baselineDistanceMeters: Float?
    private var recentDepths: [Double] = []

    func reset() {
        baselineDistanceMeters = nil
        recentDepths.removeAll()
    }

    func update(
        frame: ARFrame,
        sternumPoint2D: CGPoint,
        wristMid2D: CGPoint,
        viewportSize: CGSize
    ) -> Double? {
        if let sceneDepthCm = sceneDepthCompressionCm(
            frame: frame,
            sternumPoint2D: sternumPoint2D,
            wristMid2D: wristMid2D,
            viewportSize: viewportSize
        ) {
            return smooth(sceneDepthCm)
        }

        guard
            let sternumWorld = worldPoint(
                frame: frame,
                normalizedPoint: sternumPoint2D,
                viewportSize: viewportSize
            ),
            let wristWorld = worldPoint(
                frame: frame,
                normalizedPoint: wristMid2D,
                viewportSize: viewportSize
            )
        else {
            return nil
        }

        let currentDistance = simd_distance(sternumWorld, wristWorld)

        if baselineDistanceMeters == nil {
            baselineDistanceMeters = currentDistance
            return 0
        }

        guard let baseline = baselineDistanceMeters else {
            return nil
        }

        let compressionMeters = max(0, baseline - currentDistance)
        return smooth(Double(compressionMeters * 100))
    }

    // MARK: - Scene depth (LiDAR)

    private func sceneDepthCompressionCm(
        frame: ARFrame,
        sternumPoint2D: CGPoint,
        wristMid2D: CGPoint,
        viewportSize: CGSize
    ) -> Double? {
        guard
            let sternumMeters = depthAlongRay(
                frame: frame,
                normalizedViewportPoint: sternumPoint2D,
                viewportSize: viewportSize
            ),
            let wristMeters = depthAlongRay(
                frame: frame,
                normalizedViewportPoint: wristMid2D,
                viewportSize: viewportSize
            )
        else {
            return nil
        }

        let currentDistance = abs(sternumMeters - wristMeters)

        if baselineDistanceMeters == nil {
            baselineDistanceMeters = currentDistance
            return 0
        }

        guard let baseline = baselineDistanceMeters else { return nil }

        let compressionMeters = max(0, baseline - currentDistance)
        return Double(compressionMeters * 100)
    }

    private func depthAlongRay(
        frame: ARFrame,
        normalizedViewportPoint: CGPoint,
        viewportSize: CGSize
    ) -> Float? {
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else { return nil }

        let depthMap = depthData.depthMap
        let imagePoint = imagePoint(
            for: normalizedViewportPoint,
            frame: frame,
            viewportSize: viewportSize
        )

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let x = min(max(Int(imagePoint.x.rounded()), 0), width - 1)
        let y = min(max(Int(imagePoint.y.rounded()), 0), height - 1)

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let pointer = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
        let depth = pointer[x]
        guard depth.isFinite, depth > 0.05, depth < 5 else { return nil }
        return depth
    }

    private func imagePoint(
        for normalizedViewportPoint: CGPoint,
        frame: ARFrame,
        viewportSize: CGSize
    ) -> CGPoint {
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            return .zero
        }

        var viewportPoint = CGPoint(
            x: normalizedViewportPoint.x * viewportSize.width,
            y: normalizedViewportPoint.y * viewportSize.height
        )

        let transform = frame.displayTransform(
            for: .portrait,
            viewportSize: viewportSize
        ).inverted()

        return viewportPoint.applying(transform)
    }

    // MARK: - Hit-test fallback

    private func worldPoint(
        frame: ARFrame,
        normalizedPoint: CGPoint,
        viewportSize: CGSize
    ) -> simd_float3? {
        let screenPoint = CGPoint(
            x: normalizedPoint.x * viewportSize.width,
            y: normalizedPoint.y * viewportSize.height
        )

        let results = frame.hitTest(
            screenPoint,
            types: [.featurePoint, .estimatedHorizontalPlane, .estimatedVerticalPlane]
        )

        guard let result = results.first else {
            return nil
        }

        let t = result.worldTransform
        return simd_float3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
    }

    private func smooth(_ depthCm: Double) -> Double {
        recentDepths.append(depthCm)
        if recentDepths.count > 8 {
            recentDepths.removeFirst()
        }
        return recentDepths.reduce(0, +) / Double(recentDepths.count)
    }
}
