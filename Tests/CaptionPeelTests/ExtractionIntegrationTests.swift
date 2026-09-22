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
        XCTAssertEqual(cues[0].start, 1, accuracy: 0.05)
        XCTAssertEqual(cues[0].end, 3, accuracy: 0.05)
        XCTAssertEqual(cues[1].start, 3, accuracy: 0.05)
        XCTAssertEqual(cues[1].end, 5, accuracy: 0.05)
    }

    func testSequentialScanCapturesBriefCaptionBetweenLegacySamplePoints() async throws {
        let videoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionPeel-Brief-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: videoURL) }

        // This 0.2 s caption lies entirely between 0.25 s sample points. The
        // previous seek-based scanner could never observe it.
        try await SyntheticCaptionVideo.write(
            to: videoURL,
            framesPerSecond: 30,
            duration: 2
        ) { time in
            (time >= 1.033 && time < 1.233) ? "Grüezi" : nil
        }

        let engine = CaptionExtractionEngine(videoURL: videoURL)
        let cues = try await engine.extract(region: .suggestedCaptionRegion) { _ in }

        guard let cue = cues.first(where: { $0.text.localizedCaseInsensitiveContains("Grüezi") }) else {
            return XCTFail("Expected the brief caption to be extracted; got \(cues.map(\.text))")
        }
        XCTAssertEqual(cue.start, 1.033, accuracy: 0.05)
        XCTAssertEqual(cue.end, 1.233, accuracy: 0.05)
    }

    func testClientClipWhenProvided() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPTIONPEEL_CLIENT_FIXTURE"] else {
            throw XCTSkip("Set CAPTIONPEEL_CLIENT_FIXTURE to run the private client-clip smoke test.")
        }

        let url = URL(fileURLWithPath: path)
        let engine = CaptionExtractionEngine(videoURL: url)
        let cues = try await engine.extract(region: .suggestedCaptionRegion) { _ in }

        let duration = try await AVURLAsset(url: url).load(.duration).seconds

        XCTAssertFalse(cues.isEmpty)
        XCTAssertTrue(cues.allSatisfy { $0.start >= 0 && $0.end > $0.start })
        XCTAssertTrue(cues.allSatisfy { $0.end <= duration })
        for cue in cues {
            print("\(Timecode.string(from: cue.start)) --> \(Timecode.string(from: cue.end)) | \(cue.text.replacingOccurrences(of: "\n", with: " / "))")
        }
    }
}

private enum SyntheticCaptionVideo {
    static let width = 1_280
    static let height = 720

    static func write(to url: URL) async throws {
        let captions: [String?] = [
            nil,
            "Grüezi mitenand",
            "Grüezi mitenand",
            "S'isch guet",
            "S'isch guet",
            nil,
            nil,
        ]
        try await write(to: url, framesPerSecond: 1, duration: captions.count) { time in
            captions[min(Int(time), captions.count - 1)]
        }
    }

    static func write(
        to url: URL,
        framesPerSecond: Int,
        duration: Int,
        captionAt: (TimeInterval) -> String?
    ) async throws {
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

        for frameIndex in 0..<(duration * framesPerSecond) {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            let time = Double(frameIndex) / Double(framesPerSecond)
            let caption = captionAt(time)
            guard let buffer = makePixelBuffer(caption: caption),
                  adaptor.append(buffer, withPresentationTime: CMTime(seconds: time, preferredTimescale: 600)) else {
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
