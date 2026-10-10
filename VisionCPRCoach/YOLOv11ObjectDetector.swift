import CoreMedia
import CoreML
import CoreVideo
import Foundation
import Vision

/// Single detection from the bundled YOLOv11n Core ML model (COCO classes + NMS).
struct YOLODetection: Equatable {
    let label: String
    let confidence: Float
    /// Vision-normalized box, origin bottom-left (same space as human rectangles).
    let boundingBox: CGRect

    var isPerson: Bool { label == "person" }
}

/// Bundled `yolo11n.mlpackage` via `VNCoreMLRequest` — object / scene cues for live Coach.
final class YOLOv11ObjectDetector {
    enum DetectorError: Error {
        case modelNotFound
        case inferenceFailed(Error)
        case busy
    }

    static let shared = YOLOv11ObjectDetector()

    /// Labels that matter for CPR scene understanding (patient, surroundings, gear).
    static let sceneRelevantLabels: Set<String> = [
        "person", "bed", "couch", "chair", "backpack", "suitcase",
        "handbag", "cell phone", "sports ball", "teddy bear", "bottle"
    ]

    private var visionModel: VNCoreMLModel?
    private var isProcessing = false
    private var lastDetections: [YOLODetection] = []
    private let lock = NSLock()

    private(set) var isModelLoaded = false
    private(set) var modelName = "yolo11n"

    init() { loadModel() }

    func detect(from sampleBuffer: CMSampleBuffer) throws -> [YOLODetection] {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw DetectorError.modelNotFound
        }
        return try detect(pixelBuffer: buffer, orientation: .right)
    }

    func detect(fromPortrait pixelBuffer: CVPixelBuffer) throws -> [YOLODetection] {
        try detect(pixelBuffer: pixelBuffer, orientation: .up)
    }

    private func detect(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) throws -> [YOLODetection] {
        guard let visionModel else { throw DetectorError.modelNotFound }

        lock.lock()
        guard !isProcessing else {
            lock.unlock()
            if !lastDetections.isEmpty { return lastDetections }
            throw DetectorError.busy
        }
        isProcessing = true
        lock.unlock()
        defer {
            lock.lock()
            isProcessing = false
            lock.unlock()
        }

        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )

        do {
            try handler.perform([request])
        } catch {
            throw DetectorError.inferenceFailed(error)
        }

        let observations = request.results as? [VNRecognizedObjectObservation] ?? []
        let detections = observations.compactMap { obs -> YOLODetection? in
            let label = obs.labels.first?.identifier ?? "object"
            let confidence = obs.labels.first?.confidence ?? obs.confidence
            guard confidence >= 0.30 else { return nil }
            return YOLODetection(
                label: label,
                confidence: confidence,
                boundingBox: obs.boundingBox
            )
        }

        lastDetections = detections
        return detections
    }

    private func loadModel() {
        let url =
            Bundle.main.url(forResource: "yolo11n", withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: "yolo11n", withExtension: "mlpackage")
            ?? Bundle.main.url(forResource: "yolo11n", withExtension: "mlmodel")

        guard let url else {
            print("YOLO: yolo11n not found in bundle")
            return
        }

        do {
            let modelURL: URL
            if url.pathExtension == "mlpackage" || url.pathExtension == "mlmodel" {
                modelURL = try MLModel.compileModel(at: url)
            } else {
                modelURL = url
            }
            let ml = try MLModel(contentsOf: modelURL)
            visionModel = try VNCoreMLModel(for: ml)
            isModelLoaded = true
            print("YOLO: yolo11n ready")
        } catch {
            print("YOLO load failed: \(error)")
        }
    }
}
