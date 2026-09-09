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
        sampleInterval: TimeInterval = 0.5
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

        let start = max(0, requestedRange?.lowerBound ?? 0)
        let end = min(assetDuration, requestedRange?.upperBound ?? assetDuration)
        guard end > start else { throw ExtractionError.invalidDuration }

        let generator = makeGenerator()
        var accumulator = CueAccumulator()
        var previousFingerprint: FrameFingerprint?
        var lastOCRTime = start - 10
        var time = start

        while time <= end + 0.0001 {
            try Task.checkCancellation()
            let image = try await frame(at: time, using: generator)
            guard let cropped = crop(image, to: region) else {
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
                let boundary = max(start, (lastOCRTime + time) / 2)
                accumulator.observe(
                    result: result,
                    at: time,
                    estimatedBoundary: lastOCRTime < start ? time : boundary,
                    sampleInterval: sampleInterval
                )
                lastOCRTime = time
                previousFingerprint = fingerprint
            }

            let fraction = min(1, (time - start) / (end - start))
            progress(ExtractionProgress(
                fraction: fraction,
                phase: .scanning,
                currentTime: time,
                duration: end - start
            ))
            time += sampleInterval
        }

        progress(ExtractionProgress(fraction: 1, phase: .finishing, currentTime: end, duration: end - start))
        accumulator.finish(at: end)
        return accumulator.cleanedCues()
    }

    func recognize(at seconds: TimeInterval, region: NormalizedRect) async throws -> OCRResult {
        let generator = makeGenerator()
        let image = try await frame(at: seconds, using: generator)
        guard let cropped = crop(image, to: region) else { throw ExtractionError.frameUnavailable }
        return try await recognizer.recognizeText(in: cropped)
    }

    private func makeGenerator() -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.04, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.04, preferredTimescale: 600)
        return generator
    }

    private func frame(at seconds: TimeInterval, using generator: AVAssetImageGenerator) async throws -> CGImage {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let (image, _) = try await generator.image(at: time)
        return image
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
        estimatedBoundary: TimeInterval,
        sampleInterval: TimeInterval
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
        let end = max(current.start + 0.2, time)
        cues.append(CaptionCue(
            start: current.start,
            end: end,
            text: current.text,
            confidence: current.confidence
        ))
        active = nil
    }

    func cleanedCues() -> [CaptionCue] {
        var cleaned: [CaptionCue] = []
        for cue in cues where cue.duration >= 0.2 {
            if var previous = cleaned.last,
               cue.start - previous.end <= 0.75,
               TextSimilarity.score(previous.text, cue.text) >= 0.78 {
                previous.end = cue.end
                if cue.confidence > previous.confidence {
                    previous.text = cue.text
                    previous.confidence = cue.confidence
                }
                cleaned[cleaned.count - 1] = previous
            } else {
                cleaned.append(cue)
            }
        }
        return cleaned
    }
}
