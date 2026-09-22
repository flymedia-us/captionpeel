@preconcurrency import AVFoundation
import CoreGraphics
import CoreImage
import Foundation

enum ExtractionError: LocalizedError {
    case invalidDuration
    case frameUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidDuration:
            return "CaptionPeel could not read the video's duration."
        case .frameUnavailable:
            return "CaptionPeel could not decode a video frame."
        }
    }
}

final class CaptionExtractionEngine: @unchecked Sendable {
    typealias ProgressHandler = @Sendable (ExtractionProgress) -> Void

    // A caption occupies only a small fraction of its selected region. This is
    // deliberately below the old coarse sampling threshold so a short, small
    // caption gets an OCR check as soon as its pixels appear.
    private static let fingerprintChangeThreshold = 0.006

    private let asset: AVURLAsset
    private let recognizer: any OCRRecognizing
    /// Retained for source compatibility with callers that used to configure the
    /// seek-based sampler. Extraction now examines every decoded video frame.
    private let sampleInterval: TimeInterval

    init(
        videoURL: URL,
        recognizer: any OCRRecognizing = VisionOCRRecognizer(),
        sampleInterval: TimeInterval = 0.25
    ) {
        asset = AVURLAsset(url: videoURL)
        self.recognizer = recognizer
        self.sampleInterval = sampleInterval
    }

    func extract(
        region: NormalizedRect,
        range requestedRange: ClosedRange<TimeInterval>? = nil,
        progress: @escaping ProgressHandler
    ) async throws -> [CaptionCue] {
        progress(ExtractionProgress(fraction: 0, phase: .preparing, currentTime: 0, duration: 0))
        let assetDuration = try await asset.load(.duration).seconds
        guard assetDuration.isFinite, assetDuration > 0 else { throw ExtractionError.invalidDuration }

        let videoDuration = try await loadVideoDuration(fallbackDuration: assetDuration)

        let start = max(0, requestedRange?.lowerBound ?? 0)
        let end = min(videoDuration, requestedRange?.upperBound ?? videoDuration)
        guard end > start else { throw ExtractionError.invalidDuration }

        var accumulator = CueAccumulator()
        var previousFingerprint: FrameFingerprint?
        var OCRFingerprint: FrameFingerprint?
        var previousObservation: TimedOCRResult?
        var lastOCRTime = start - 10
        let reader = try await makeFrameReader(range: start...end)
        var lastFrameTime = start

        while let frame = try reader.nextFrame() {
            try Task.checkCancellation()
            guard frame.time <= end else { break }
            let fingerprint = FrameFingerprint(pixelBuffer: frame.pixelBuffer, region: region)
            let adjacentFrameChanged: Bool
            if let fingerprint, let previousFingerprint {
                adjacentFrameChanged = fingerprint.distance(from: previousFingerprint) >= Self.fingerprintChangeThreshold
            } else {
                adjacentFrameChanged = true
            }
            let changedSinceOCR: Bool
            if let fingerprint, let OCRFingerprint {
                changedSinceOCR = fingerprint.distance(from: OCRFingerprint) >= Self.fingerprintChangeThreshold
            } else {
                changedSinceOCR = true
            }

            // Always advance the adjacent-frame fingerprint. Keeping it at the
            // last OCR frame turns a single caption change into OCR work on every
            // following frame until the next periodic verification.
            previousFingerprint = fingerprint

            if adjacentFrameChanged || changedSinceOCR || frame.time - lastOCRTime >= 2.0 {
                try Task.checkCancellation()
                // The first accurate Vision request may load its on-device model.
                // It has no completed scan time to report yet, so expose it as a
                // separate indeterminate phase instead of appearing frozen at 0%.
                if previousObservation == nil {
                    progress(ExtractionProgress(
                        fraction: 0,
                        phase: .preparingVision,
                        currentTime: 0,
                        duration: end - start
                    ))
                }
                let result: OCRResult
                do {
                    result = try await recognizer.recognizeText(in: frame.pixelBuffer, region: region)
                } catch {
                    // Retain the established CGImage route as a compatibility
                    // fallback for another local recognizer or a Vision runtime
                    // that cannot consume this particular pixel-buffer format.
                    guard let image = reader.image(for: frame),
                          let cropped = crop(image, to: region) else {
                        throw ExtractionError.frameUnavailable
                    }
                    result = try await recognizer.recognizeText(in: cropped)
                }
                // This is a sequential reader pass: `frame.time` is the actual
                // presentation timestamp of this decoded frame. A text change is
                // therefore already frame-accurate, without a binary search made
                // of expensive random seeks.
                let boundary = previousObservation == nil ? start : frame.time
                accumulator.observe(
                    result: result,
                    at: frame.time,
                    estimatedBoundary: boundary
                )
                lastOCRTime = frame.time
                OCRFingerprint = fingerprint
                previousObservation = TimedOCRResult(time: frame.time, result: result)
            }

            lastFrameTime = frame.time
            let fraction = min(1, max(0, (frame.time - start) / (end - start)))
            progress(ExtractionProgress(
                fraction: fraction,
                phase: .scanning,
                currentTime: frame.time,
                duration: end - start
            ))
        }

        progress(ExtractionProgress(fraction: 1, phase: .finishing, currentTime: max(lastFrameTime, end), duration: end - start))
        accumulator.finish(at: end)
        return accumulator.cleanedCues()
    }

    func recognize(at seconds: TimeInterval, region: NormalizedRect) async throws -> OCRResult {
        let generator = makeGenerator()
        let frame = try await frame(at: seconds, using: generator)
        guard let cropped = crop(frame.image, to: region) else { throw ExtractionError.frameUnavailable }
        return try await recognizer.recognizeText(in: cropped)
    }

    private func makeGenerator() -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return generator
    }

    private func loadVideoDuration(fallbackDuration: TimeInterval) async throws -> TimeInterval {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExtractionError.frameUnavailable
        }
        let timeRange = try await track.load(.timeRange)
        let trackEnd = timeRange.end.seconds
        return trackEnd.isFinite && trackEnd > 0 ? min(trackEnd, fallbackDuration) : fallbackDuration
    }

    private func makeFrameReader(range: ClosedRange<TimeInterval>) async throws -> SequentialFrameReader {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExtractionError.frameUnavailable
        }
        return try await SequentialFrameReader(asset: asset, track: track, range: range)
    }

    private func sameCaption(_ lhs: OCRResult, _ rhs: OCRResult) -> Bool {
        let left = lhs.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty || right.isEmpty { return left.isEmpty && right.isEmpty }
        return TextSimilarity.score(left, right) >= 0.78
    }

    private func frame(at seconds: TimeInterval, using generator: AVAssetImageGenerator) async throws -> VideoFrame {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let (image, actualTime) = try await generator.image(at: time)
        let actualSeconds = actualTime.seconds
        return VideoFrame(
            image: image,
            time: actualSeconds.isFinite ? actualSeconds : seconds
        )
    }

    private func crop(_ image: CGImage, to normalizedRegion: NormalizedRect) -> CGImage? {
        let region = normalizedRegion.clamped()
        let imageWidth = Double(image.width)
        let imageHeight = Double(image.height)
        let rect = CGRect(
            x: region.x * imageWidth,
            y: region.y * imageHeight,
            width: region.width * imageWidth,
            height: region.height * imageHeight
        ).integral.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        guard rect.width > 1, rect.height > 1 else { return nil }
        return image.cropping(to: rect)
    }
}

/// Decodes forward once instead of seeking to every sample point. The video
/// composition gives this path the same preferred-transform behavior as the
/// image generator used for one-off cue re-reads.
private final class SequentialFrameReader: @unchecked Sendable {
    private let reader: AVAssetReader
    private let output: AVAssetReaderVideoCompositionOutput
    private let context = CIContext(options: [.cacheIntermediates: false])

    init(asset: AVAsset, track: AVAssetTrack, range: ClosedRange<TimeInterval>) async throws {
        reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: range.lowerBound, preferredTimescale: 600),
            end: CMTime(seconds: range.upperBound, preferredTimescale: 600)
        )

        output = AVAssetReaderVideoCompositionOutput(
            videoTracks: [track],
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
        )
        output.videoComposition = try await withCheckedThrowingContinuation { continuation in
            AVMutableVideoComposition.videoComposition(withPropertiesOf: asset) { composition, error in
                if let composition {
                    continuation.resume(returning: composition)
                } else {
                    continuation.resume(throwing: error ?? ExtractionError.frameUnavailable)
                }
            }
        }
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw ExtractionError.frameUnavailable }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? ExtractionError.frameUnavailable
        }
    }

    deinit {
        if reader.status == .reading { reader.cancelReading() }
    }

    func nextFrame() throws -> DecodedVideoFrame? {
        guard let sample = output.copyNextSampleBuffer() else {
            if reader.status == .failed {
                throw reader.error ?? ExtractionError.frameUnavailable
            }
            return nil
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else {
            throw ExtractionError.frameUnavailable
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        guard timestamp.isFinite else { throw ExtractionError.frameUnavailable }
        return DecodedVideoFrame(pixelBuffer: pixelBuffer, time: timestamp)
    }

    func image(for frame: DecodedVideoFrame) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: frame.pixelBuffer)
        return context.createCGImage(ciImage, from: ciImage.extent)
    }

}

private struct DecodedVideoFrame {
    var pixelBuffer: CVPixelBuffer
    var time: TimeInterval
}

private struct VideoFrame {
    var image: CGImage
    var time: TimeInterval
}

private struct TimedOCRResult {
    var time: TimeInterval
    var result: OCRResult
}

private struct CueAccumulator {
    private struct ActiveCue {
        var start: TimeInterval
        var lastSeen: TimeInterval
        var text: String
        var confidence: Float
    }

    private var cues: [CaptionCue] = []
    private var active: ActiveCue?

    mutating func observe(
        result: OCRResult,
        at time: TimeInterval,
        estimatedBoundary: TimeInterval
    ) {
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            closeActive(at: estimatedBoundary)
            return
        }

        guard var current = active else {
            active = ActiveCue(start: estimatedBoundary, lastSeen: time, text: text, confidence: result.confidence)
            return
        }

        if TextSimilarity.score(current.text, text) >= 0.78 {
            current.lastSeen = time
            if result.confidence > current.confidence {
                current.text = text
                current.confidence = result.confidence
            }
            active = current
        } else {
            closeActive(at: estimatedBoundary)
            active = ActiveCue(start: estimatedBoundary, lastSeen: time, text: text, confidence: result.confidence)
        }
    }

    mutating func finish(at time: TimeInterval) {
        closeActive(at: time)
    }

    mutating private func closeActive(at time: TimeInterval) {
        guard let current = active else { return }
        let end = max(current.start, time)
        cues.append(CaptionCue(
            start: current.start,
            end: end,
            text: current.text,
            confidence: current.confidence
        ))
        active = nil
    }

    func cleanedCues() -> [CaptionCue] {
        // Keep real blank intervals intact. Merging matching text across a gap
        // makes an exported cue start or end when no caption is on screen.
        // A sequential pass can accurately recover a brief, legitimate caption.
        // Keep anything lasting at least two 30 fps frames instead of discarding
        // it solely because the former quarter-second sampler could not see it.
        cues.filter { $0.duration >= 0.05 }
    }
}
