import CoreGraphics
import CoreVideo
import Foundation

struct FrameFingerprint: Sendable {
    private let samples: [UInt8]

    init?(image: CGImage, width: Int = 16, height: Int = 9) {
        var bytes = Array(repeating: UInt8(0), count: width * height)
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        samples = bytes
    }

    /// Samples the selected region directly from the reader's BGRA output. This
    /// keeps the common unchanged-frame path free of CGImage creation and crop
    /// allocation; the expensive image conversion is reserved for OCR candidates.
    init?(pixelBuffer: CVPixelBuffer, region: NormalizedRect, width: Int = 32, height: Int = 18) {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            return nil
        }
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        let selection = region.clamped()
        let minX = Int(selection.x * Double(sourceWidth))
        let minY = Int(selection.y * Double(sourceHeight))
        let selectedWidth = max(1, Int(selection.width * Double(sourceWidth)))
        let selectedHeight = max(1, Int(selection.height * Double(sourceHeight)))
        guard minX < sourceWidth, minY < sourceHeight else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        var result = [UInt8]()
        result.reserveCapacity(width * height)
        for sampleY in 0..<height {
            let y = min(sourceHeight - 1, minY + (sampleY * selectedHeight + selectedHeight / 2) / height)
            for sampleX in 0..<width {
                let x = min(sourceWidth - 1, minX + (sampleX * selectedWidth + selectedWidth / 2) / width)
                let pixel = bytes + y * bytesPerRow + x * 4
                // BT.709-ish integer luminance for BGRA pixels.
                let luminance = (54 * Int(pixel[2]) + 183 * Int(pixel[1]) + 19 * Int(pixel[0])) >> 8
                result.append(UInt8(clamping: luminance))
            }
        }
        samples = result
    }

    func distance(from other: FrameFingerprint) -> Double {
        guard samples.count == other.samples.count, !samples.isEmpty else { return 1 }
        let total = zip(samples, other.samples).reduce(0) { result, pair in
            result + abs(Int(pair.0) - Int(pair.1))
        }
        return Double(total) / Double(samples.count * 255)
    }
}
