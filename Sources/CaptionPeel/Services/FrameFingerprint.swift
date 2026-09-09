import CoreGraphics
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

    func distance(from other: FrameFingerprint) -> Double {
        guard samples.count == other.samples.count, !samples.isEmpty else { return 1 }
        let total = zip(samples, other.samples).reduce(0) { result, pair in
            result + abs(Int(pair.0) - Int(pair.1))
        }
        return Double(total) / Double(samples.count * 255)
    }
}
