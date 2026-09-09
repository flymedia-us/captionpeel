@preconcurrency import AVFoundation
import CoreGraphics
import CoreText
import XCTest
@testable import CaptionPeel

final class ExtractionIntegrationTests: XCTestCase {
    func testSyntheticVideoExtractsSwissGermanCaptions() async throws {
        let keepFixture = ProcessInfo.processInfo.environment["CAPTIONPEEL_KEEP_FIXTURE"] == "1"
        let videoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(keepFixture ? "CaptionPeel-Smoke.mp4" : "CaptionPeel-Smoke-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: videoURL)
        defer {
            if !keepFixture { try? FileManager.default.removeItem(at: videoURL) }
        }

        try await SyntheticCaptionVideo.write(to: videoURL)
        let engine = CaptionExtractionEngine(videoURL: videoURL, sampleInterval: 0.5)
        let cues = try await engine.extract(region: .suggestedCaptionRegion) { _ in }

        XCTAssertGreaterThanOrEqual(cues.count, 2)
        XCTAssertTrue(
            cues.contains { $0.text.localizedCaseInsensitiveContains("Grüezi") },
            "Expected a cue containing ‘Grüezi’; got \(cues.map(\.text))"
        )
        XCTAssertTrue(
            cues.contains { $0.text.localizedCaseInsensitiveContains("guet") },
            "Expected a cue containing ‘guet’; got \(cues.map(\.text))"
        )
        XCTAssertTrue(cues.allSatisfy { $0.end > $0.start })
    }
}

private enum SyntheticCaptionVideo {
    static let width = 1_280
    static let height = 720

    static func write(to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )

        guard writer.canAdd(input) else {
            throw NSError(domain: "CaptionPeelTests", code: 1)
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "CaptionPeelTests", code: 2)
        }
        writer.startSession(atSourceTime: .zero)

        let captions: [String?] = [
            nil,
            "Grüezi mitenand",
            "Grüezi mitenand",
            "S'isch guet",
            "S'isch guet",
            nil,
            nil,
        ]

        for (second, caption) in captions.enumerated() {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            guard let buffer = makePixelBuffer(caption: caption),
                  adaptor.append(buffer, withPresentationTime: CMTime(seconds: Double(second), preferredTimescale: 600)) else {
                throw writer.error ?? NSError(domain: "CaptionPeelTests", code: 3)
            }
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? NSError(domain: "CaptionPeelTests", code: 4)
        }
    }

    private static func makePixelBuffer(caption: String?) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        ) == kCVReturnSuccess,
              let pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
              let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
              ) else {
            return nil
        }

        context.setFillColor(CGColor(gray: 0.06, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let caption else { return pixelBuffer }
        let textAttributes = [
            kCTFontAttributeName: CTFontCreateWithName("Helvetica Neue" as CFString, 58, nil),
            kCTForegroundColorAttributeName: CGColor(gray: 1, alpha: 1),
        ] as CFDictionary
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(
            kCFAllocatorDefault,
            caption as CFString,
            textAttributes
        ))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        context.textPosition = CGPoint(x: (CGFloat(width) - bounds.width) / 2, y: 92)
        CTLineDraw(line, context)
        return pixelBuffer
    }
}
