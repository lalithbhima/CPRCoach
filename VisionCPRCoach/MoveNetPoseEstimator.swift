import CoreMedia
import CoreVideo
import Foundation
import TensorFlowLite

/// Exact port of `run_movenet()` in live_movenet_cpr.py.
final class MoveNetPoseEstimator {
    enum EstimatorError: Error {
        case modelNotFound
        case preprocessFailed
        case inferenceFailed(Error)
        case postprocessFailed
        case busy
    }

    static let shared = MoveNetPoseEstimator()
    static let minKeypointScore: Float = 0.2

    private var interpreter: Interpreter?
    private var inputSize = 256
    private var inputKind: MoveNetImageProcessor.InputKind = .uint8
    private var isProcessing = false
    private var lastRescuerPose: MoveNetPose?
    private var lastPatientPose: MoveNetPose?
    private var lastPose: MoveNetPose?
    private let lock = NSLock()

    private(set) var isModelLoaded = false
    private(set) var modelName = ""
    var lastKnownPose: MoveNetPose? { lastRescuerPose ?? lastPose }

    init() { loadModel() }

    func resetCrop() {
        lastPose = nil
        lastRescuerPose = nil
        lastPatientPose = nil
    }

    func estimatePatientCropPose(fromPortrait pixelBuffer: CVPixelBuffer) throws -> MoveNetPose {
        do {
            let pose = try runInference(on: pixelBuffer)
            lastPatientPose = pose
            return pose
        } catch EstimatorError.busy {
            if let lastPatientPose { return lastPatientPose }
            throw EstimatorError.busy
        }
    }

    func estimatePose(from sampleBuffer: CMSampleBuffer) throws -> MoveNetPose {
        guard let portrait = MoveNetCameraFrame.makePortraitBuffer(from: sampleBuffer) else {
            throw EstimatorError.preprocessFailed
        }
        return try estimatePose(fromPortrait: portrait)
    }

    func estimatePose(fromPortrait pixelBuffer: CVPixelBuffer) throws -> MoveNetPose {
        do {
            let pose = try runInference(on: pixelBuffer)
            lastPose = pose
            lastRescuerPose = pose
            return pose
        } catch EstimatorError.busy {
            if let lastRescuerPose { return lastRescuerPose }
            throw EstimatorError.busy
        }
    }

    private func runInference(on pixelBuffer: CVPixelBuffer) throws -> MoveNetPose {
        guard let interpreter else { throw EstimatorError.modelNotFound }

        lock.lock()
        guard !isProcessing else {
            lock.unlock()
            throw EstimatorError.busy
        }
        isProcessing = true
        lock.unlock()
        defer {
            lock.lock()
            isProcessing = false
            lock.unlock()
        }

        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)

        guard let packed = MoveNetImageProcessor.resizeWithPad(
            pixelBuffer: pixelBuffer,
            targetSize: inputSize,
            inputKind: inputKind
        ) else {
            throw EstimatorError.preprocessFailed
        }

        do {
            try interpreter.copy(packed.data, toInputAt: 0)
            try interpreter.invoke()
            let output = try interpreter.output(at: 0)
            let raw = outputFloats(from: output)
            guard raw.count >= 51 else { throw EstimatorError.postprocessFailed }

            // MoveNet outputs are normalized to the padded square. Undo the letterbox so the
            // keypoints land exactly on the original portrait frame (otherwise they squish inward).
            let pad = packed.pad
            let target = Double(pad.targetSize)
            let scale = min(target / Double(pad.imageWidth), target / Double(pad.imageHeight))
            let scaledW = (Double(pad.imageWidth) * scale).rounded()
            let scaledH = (Double(pad.imageHeight) * scale).rounded()
            let padLeft = (target - scaledW) / 2
            let padTop = (target - scaledH) / 2

            var keypoints: [MoveNetKeypoint] = []
            for joint in MoveNetJoint.allCases {
                let i = joint.rawValue * 3
                let yNorm = Double(raw[i])
                let xNorm = Double(raw[i + 1])
                let score = raw[i + 2]

                // square-normalized -> square-pixels -> remove pad -> original-frame-normalized
                let xUnpadded = (xNorm * target - padLeft) / max(scaledW, 1)
                let yUnpadded = (yNorm * target - padTop) / max(scaledH, 1)

                keypoints.append(MoveNetKeypoint(
                    joint: joint,
                    x: CGFloat(min(max(xUnpadded, 0), 1)),
                    y: CGFloat(min(max(yUnpadded, 0), 1)),
                    confidence: score
                ))
            }

            return MoveNetPose(
                keypoints: keypoints,
                frameWidth: w,
                frameHeight: h,
                inferenceMs: 0
            )
        } catch let e as EstimatorError {
            throw e
        } catch {
            throw EstimatorError.inferenceFailed(error)
        }
    }

    private func loadModel() {
        for name in ["movenet_thunder", "movenet_lightning_int8"] {
            guard let path = Bundle.main.path(forResource: name, ofType: "tflite") else { continue }
            if loadInterpreter(at: path, name: "\(name).tflite") { return }
        }
    }

    private func loadInterpreter(at path: String, name: String) -> Bool {
        do {
            var options = Interpreter.Options()
            options.threadCount = 4
            let interp = try Interpreter(modelPath: path, options: options)
            try interp.allocateTensors()
            let input = try interp.input(at: 0)
            let dims = input.shape.dimensions
            if dims.count >= 4 {
                inputSize = max(dims[dims.count - 3], dims[dims.count - 2])
            }
            inputKind = inputKind(from: input.dataType)
            interpreter = interp
            isModelLoaded = true
            modelName = name
            print("MoveNet: \(name) ready \(inputSize)×\(inputSize)")
            return true
        } catch {
            return false
        }
    }

    private func inputKind(from t: Tensor.DataType) -> MoveNetImageProcessor.InputKind {
        switch t {
        case .uInt8: return .uint8
        case .float32: return .float32
        case .int32: return .int32
        default: return .uint8
        }
    }

    private func outputFloats(from tensor: Tensor) -> [Float32] {
        switch tensor.dataType {
        case .float32: return tensor.data.toArray(type: Float32.self)
        case .uInt8: return [UInt8](tensor.data).map { Float32($0) }
        default: return tensor.data.toArray(type: Float32.self)
        }
    }
}

extension Data {
    func toArray<T>(type: T.Type) -> [T] {
        guard count % MemoryLayout<T>.stride == 0 else { return [] }
        return withUnsafeBytes { Array($0.bindMemory(to: T.self)) }
    }
}
