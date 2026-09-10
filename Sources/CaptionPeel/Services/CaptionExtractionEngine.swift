@preconcurrency import AVFoundation
import CoreGraphics
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

    private let asset: AVURLAsset
    private let recognizer: any OCRRecognizing
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

        let videoTiming = try await loadVideoTiming(fallbackDuration: assetDuration)
        let videoDuration = videoTiming.duration

        let start = max(0, requestedRange?.lowerBound ?? 0)
        let end = min(videoDuration, requestedRange?.upperBound ?? videoDuration)
        guard end > start else { throw ExtractionError.invalidDuration }

        let generator = makeGenerator()
        var accumulator = CueAccumulator()
        var previousFingerprint: FrameFingerprint?
        var previousObservation: TimedOCRResult?
        var lastOCRTime = start - 10
        var time = start

        while true {
            try Task.checkCancellation()
            let frame = try await frame(at: time, using: generator)
            guard let cropped = crop(frame.image, to: region) else {
                throw ExtractionError.frameUnavailable
            }

            let fingerprint = FrameFingerprint(image: cropped)
            let imageChanged: Bool
            if let fingerprint, let previousFingerprint {
                imageChanged = fingerprint.distance(from: previousFingerprint) >= 0.018
            } else {
                imageChanged = true
            }

            if imageChanged || time - lastOCRTime >= 2.0 {
                try Task.checkCancellation()
                let result = try await recognizer.recognizeText(in: cropped)
                let boundary: TimeInterval
                if let previousObservation,
                   !sameCaption(previousObservation.result, result) {
                    boundary = try await refineBoundary(
                        from: previousObservation,
                        to: TimedOCRResult(time: frame.time, result: result),
                        region: region,
                        generator: generator,
                        frameDuration: videoTiming.frameDuration
                    )
                } else {
                    boundary = previousObservation == nil ? start : time
                }
                accumulator.observe(
                    result: result,
                    at: frame.time,
                    estimatedBoundary: boundary
                )
                lastOCRTime = time
                previousFingerprint = fingerprint
                previousObservation = TimedOCRResult(time: frame.time, result: result)
            }

            let fraction = min(1, (time - start) / (end - start))
            progress(ExtractionProgress(
                fraction: fraction,
                phase: .scanning,
                currentTime: time,
                duration: end - start
            ))
            if time >= end { break }
            time = min(end, time + sampleInterval)
        }

        progress(ExtractionProgress(fraction: 1, phase: .finishing, currentTime: end, duration: end - start))
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

    private func loadVideoTiming(fallbackDuration: TimeInterval) async throws -> VideoTiming {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExtractionError.frameUnavailable
        }
        let timeRange = try await track.load(.timeRange)
        let minFrameDuration = try await track.load(.minFrameDuration).seconds
        let nominalFrameRate = Double(try await track.load(.nominalFrameRate))
        let frameDuration: TimeInterval
        if minFrameDuration.isFinite, minFrameDuration > 0 {
            frameDuration = minFrameDuration
        } else if nominalFrameRate.isFinite, nominalFrameRate > 0 {
            frameDuration = 1 / nominalFrameRate
        } else {
            frameDuration = 1 / 30
        }
        let trackEnd = timeRange.end.seconds
        let duration = trackEnd.isFinite && trackEnd > 0 ? min(trackEnd, fallbackDuration) : fallbackDuration
        return VideoTiming(duration: duration, frameDuration: frameDuration)
    }

    private func refineBoundary(
        from previous: TimedOCRResult,
        to current: TimedOCRResult,
        region: NormalizedRect,
        generator: AVAssetImageGenerator,
        frameDuration: TimeInterval
    ) async throws -> TimeInterval {
        var earlier = previous.time
        var later = current.time
        let targetAccuracy = max(frameDuration, 0.001)

        while later - earlier > targetAccuracy {
            try Task.checkCancellation()
            let midpoint = (earlier + later) / 2
            let frame = try await frame(at: midpoint, using: generator)
            guard frame.time > earlier, frame.time < later else { break }
            guard let cropped = crop(frame.image, to: region) else {
                throw ExtractionError.frameUnavailable
            }
            let result = try await recognizer.recognizeText(in: cropped)
            if sameCaption(result, current.result) {
                later = frame.time
            } else {
                earlier = frame.time
            }
        }

        return later
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

private struct VideoTiming {
    var duration: TimeInterval
    var frameDuration: TimeInterval
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
        cues.filter { $0.duration >= 0.2 }
    }
}
