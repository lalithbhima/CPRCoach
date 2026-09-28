import Accelerate
import CoreImage
import CoreVideo

/// Matches Python `tf.image.resize_with_pad` + uint8 RGB input (live_movenet_cpr.py).
enum MoveNetImageProcessor {
    enum InputKind {
        case uint8
        case float32
        case int32
    }

    struct PadInfo {
        let imageWidth: Int
        let imageHeight: Int
        let targetSize: Int
    }

    /// Letterbox-resize a normalized crop of the frame to `targetSize`×`targetSize`.
    static func resizeWithPad(
        pixelBuffer: CVPixelBuffer,
        cropRegion: MoveNetCropRegion,
        targetSize: Int,
        inputKind: InputKind
    ) -> (data: Data, pad: PadInfo, crop: MoveNetCropRegion)? {
        guard let cropped = cropPixelBuffer(pixelBuffer, region: cropRegion) else { return nil }
        guard let packed = resizeWithPad(
            pixelBuffer: cropped,
            targetSize: targetSize,
            inputKind: inputKind
        ) else { return nil }
        return (packed.data, packed.pad, cropRegion)
    }

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private static func cropPixelBuffer(_ buffer: CVPixelBuffer, region: MoveNetCropRegion) -> CVPixelBuffer? {
        let fullW = CVPixelBufferGetWidth(buffer)
        let fullH = CVPixelBufferGetHeight(buffer)

        let x = max(0, Int((region.xMin * CGFloat(fullW)).rounded()))
        let y = max(0, Int((region.yMin * CGFloat(fullH)).rounded()))
        let w = max(1, min(fullW - x, Int((region.width * CGFloat(fullW)).rounded())))
        let h = max(1, min(fullH - y, Int((region.height * CGFloat(fullH)).rounded())))

        let cropRect = CGRect(x: x, y: y, width: w, height: h)
        let ci = CIImage(cvPixelBuffer: buffer).cropped(to: cropRect)

        var dst: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            w,
            h,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &dst
        )
        guard status == kCVReturnSuccess, let dst else { return nil }

        ciContext.render(ci, to: dst)
        return dst
    }

    /// Letterbox-resize entire frame to `targetSize`×`targetSize` — same as the working Python demo.
    static func resizeWithPad(
        pixelBuffer: CVPixelBuffer,
        targetSize: Int,
        inputKind: InputKind
    ) -> (data: Data, pad: PadInfo)? {
        let imgW = CVPixelBufferGetWidth(pixelBuffer)
        let imgH = CVPixelBufferGetHeight(pixelBuffer)

        let scale = min(Double(targetSize) / Double(imgW), Double(targetSize) / Double(imgH))
        let scaledW = max(1, Int((Double(imgW) * scale).rounded()))
        let scaledH = max(1, Int((Double(imgH) * scale).rounded()))
        let padLeft = (targetSize - scaledW) / 2
        let padTop = (targetSize - scaledH) / 2

        let scaledRowBytes = scaledW * 4
        guard let scaledData = malloc(scaledH * scaledRowBytes) else { return nil }
        defer { free(scaledData) }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let srcRowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)

        var srcBuffer = vImage_Buffer(
            data: base,
            height: vImagePixelCount(imgH),
            width: vImagePixelCount(imgW),
            rowBytes: srcRowBytes
        )
        var scaledBuffer = vImage_Buffer(
            data: scaledData,
            height: vImagePixelCount(scaledH),
            width: vImagePixelCount(scaledW),
            rowBytes: scaledRowBytes
        )

        guard vImageScale_ARGB8888(&srcBuffer, &scaledBuffer, nil, vImage_Flags(kvImageHighQualityResampling)) == kvImageNoError else {
            return nil
        }

        let canvasBytes = targetSize * 4
        guard let canvas = calloc(targetSize, canvasBytes) else { return nil }
        defer { free(canvas) }

        let dst = canvas.assumingMemoryBound(to: UInt8.self)
        let src = scaledData.assumingMemoryBound(to: UInt8.self)

        for row in 0..<scaledH {
            let srcOff = row * scaledRowBytes
            let dstOff = (padTop + row) * canvasBytes + padLeft * 4
            memcpy(dst.advanced(by: dstOff), src.advanced(by: srcOff), scaledRowBytes)
        }

        guard let tensor = tensorData(
            from: canvas,
            width: targetSize,
            height: targetSize,
            inputKind: inputKind
        ) else { return nil }

        return (tensor, PadInfo(imageWidth: imgW, imageHeight: imgH, targetSize: targetSize))
    }

    private static func tensorData(
        from data: UnsafeMutableRawPointer,
        width: Int,
        height: Int,
        inputKind: InputKind
    ) -> Data? {
        let pixelCount = width * height
        let src = data.assumingMemoryBound(to: UInt8.self)

        switch inputKind {
        case .uint8:
            var bytes = [UInt8](repeating: 0, count: pixelCount * 3)
            var di = 0
            for i in 0..<pixelCount {
                let si = i * 4
                bytes[di] = src[si + 2]
                bytes[di + 1] = src[si + 1]
                bytes[di + 2] = src[si]
                di += 3
            }
            return Data(bytes)

        case .float32:
            var floats = [Float32](repeating: 0, count: pixelCount * 3)
            var di = 0
            for i in 0..<pixelCount {
                let si = i * 4
                floats[di] = Float32(src[si + 2])
                floats[di + 1] = Float32(src[si + 1])
                floats[di + 2] = Float32(src[si])
                di += 3
            }
            return Data(bytes: floats, count: floats.count * MemoryLayout<Float32>.size)

        case .int32:
            var ints = [Int32](repeating: 0, count: pixelCount * 3)
            var di = 0
            for i in 0..<pixelCount {
                let si = i * 4
                ints[di] = Int32(src[si + 2])
                ints[di + 1] = Int32(src[si + 1])
                ints[di + 2] = Int32(src[si])
                di += 3
            }
            return Data(bytes: ints, count: ints.count * MemoryLayout<Int32>.size)
        }
    }
}