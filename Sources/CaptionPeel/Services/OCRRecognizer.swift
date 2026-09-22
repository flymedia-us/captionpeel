import CoreGraphics
import CoreVideo
import Foundation
import Vision

struct OCRResult: Sendable {
    var text: String
    var confidence: Float

    static let empty = OCRResult(text: "", confidence: 0)
}

protocol OCRRecognizing: Sendable {
    func recognizeText(in image: CGImage) async throws -> OCRResult
    func recognizeText(in pixelBuffer: CVPixelBuffer, region: NormalizedRect) async throws -> OCRResult
}

extension OCRRecognizing {
    /// Non-Vision recognizers can retain the original CGImage-only integration.
    /// The extraction engine will crop an image and retry when this is thrown.
    func recognizeText(in pixelBuffer: CVPixelBuffer, region: NormalizedRect) async throws -> OCRResult {
        throw OCRRecognitionError.directFrameUnsupported
    }
}

enum OCRRecognitionError: Error {
    case directFrameUnsupported
}

final class VisionOCRRecognizer: OCRRecognizing, @unchecked Sendable {
    func recognizeText(in image: CGImage) async throws -> OCRResult {
        try await recognizeText { request in
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
        }
    }

    /// Vision can inspect the selected rectangle in the decoded buffer directly.
    /// This avoids allocating a full-resolution CGImage just to crop it for OCR.
    /// Vision's region-of-interest coordinate system, like the Core Graphics crop
    /// path this replaces, has its origin at the lower left.
    func recognizeText(in pixelBuffer: CVPixelBuffer, region: NormalizedRect) async throws -> OCRResult {
        let selection = region.clamped()
        let buffer = SendablePixelBuffer(pixelBuffer)
        let visionRegion = CGRect(
            x: selection.x,
            y: selection.y,
            width: selection.width,
            height: selection.height
        )
        return try await recognizeText { request in
            request.regionOfInterest = visionRegion
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer.value, options: [:])
            try handler.perform([request])
        }
    }

    private func recognizeText(
        perform: @escaping @Sendable (VNRecognizeTextRequest) throws -> Void
    ) async throws -> OCRResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.recognitionLanguages = ["de-CH", "de-DE", "en-US", "fr-FR", "it-IT"]
                    request.usesLanguageCorrection = false
                    request.minimumTextHeight = 0.025

                    try perform(request)

                    let observations = (request.results ?? [])
                        .compactMap { observation -> (String, Float, CGRect)? in
                            guard let candidate = observation.topCandidates(1).first else { return nil }
                            return (candidate.string, candidate.confidence, observation.boundingBox)
                        }
                        .sorted { lhs, rhs in
                            if abs(lhs.2.midY - rhs.2.midY) > 0.035 {
                                return lhs.2.midY > rhs.2.midY
                            }
                            return lhs.2.minX < rhs.2.minX
                        }

                    guard !observations.isEmpty else {
                        continuation.resume(returning: .empty)
                        return
                    }

                    let text = observations.map(\.0).joined(separator: "\n")
                    let confidence = observations.map(\.1).reduce(0, +) / Float(observations.count)
                    continuation.resume(returning: OCRResult(text: text, confidence: confidence))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// Retains the Core Video buffer while Vision processes it on its worker queue.
private final class SendablePixelBuffer: @unchecked Sendable {
    let value: CVPixelBuffer

    init(_ value: CVPixelBuffer) {
        self.value = value
    }
}
