import Foundation
import Vision
import CoreMedia

final class PoseAnalyzer {
    private let request = VNDetectHumanBodyPoseRequest()

    func processFrame(
        _ sampleBuffer: CMSampleBuffer,
        completion: @escaping (BodyJoints?) -> Void
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            completion(nil)
            return
        }

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .right,
            options: [:]
        )

        do {
            try handler.perform([request])

            guard let observation = request.results?.first else {
                completion(nil)
                return
            }

            let points = try observation.recognizedPoints(.all)

            guard
                let ls = points[.leftShoulder], ls.confidence > 0.25,
                let rs = points[.rightShoulder], rs.confidence > 0.25,
                let le = points[.leftElbow], le.confidence > 0.25,
                let re = points[.rightElbow], re.confidence > 0.25,
                let lw = points[.leftWrist], lw.confidence > 0.25,
                let rw = points[.rightWrist], rw.confidence > 0.25
            else {
                completion(nil)
                return
            }

            let lh = points[.leftHip]
            let rh = points[.rightHip]
            let neck = points[.neck]

            let confidences = [ls, rs, le, re, lw, rw].map { Double($0.confidence) }
            let avgConf = confidences.reduce(0, +) / Double(confidences.count)

            let joints = BodyJoints(
                leftShoulder: point(from: ls),
                rightShoulder: point(from: rs),
                leftElbow: point(from: le),
                rightElbow: point(from: re),
                leftWrist: point(from: lw),
                rightWrist: point(from: rw),
                leftHip: lh.map { point(from: $0) },
                rightHip: rh.map { point(from: $0) },
                neck: neck.map { point(from: $0) },
                averageConfidence: Double(avgConf)
            )

            completion(joints)
        } catch {
            print("PoseAnalyzer error: \(error)")
            completion(nil)
        }
    }

    private func point(from recognized: VNRecognizedPoint) -> CGPoint {
        CGPoint(x: recognized.location.x, y: recognized.location.y)
    }
}
