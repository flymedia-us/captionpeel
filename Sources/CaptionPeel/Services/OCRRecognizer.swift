import CoreGraphics
import Foundation
import Vision

struct OCRResult: Sendable {
    var text: String
    var confidence: Float

    static let empty = OCRResult(text: "", confidence: 0)
}

protocol OCRRecognizing: Sendable {
    func recognizeText(in image: CGImage) async throws -> OCRResult
}

final class VisionOCRRecognizer: OCRRecognizing, @unchecked Sendable {
    func recognizeText(in image: CGImage) async throws -> OCRResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.recognitionLanguages = ["de-CH", "de-DE", "en-US", "fr-FR", "it-IT"]
                    request.usesLanguageCorrection = false
                    request.minimumTextHeight = 0.025

                    let handler = VNImageRequestHandler(cgImage: image, options: [:])
                    try handler.perform([request])

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
