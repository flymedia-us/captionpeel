import Foundation

struct CaptionCue: Identifiable, Equatable, Sendable {
    var id = UUID()
    var start: TimeInterval
    var end: TimeInterval
    var text: String
    var confidence: Float

    var duration: TimeInterval {
        max(0, end - start)
    }
}

struct NormalizedRect: Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let suggestedCaptionRegion = NormalizedRect(
        x: 0.08,
        y: 0.68,
        width: 0.84,
        height: 0.24
    )

    func clamped(minimumSize: Double = 0.04) -> NormalizedRect {
        let newWidth = min(max(width, minimumSize), 1)
        let newHeight = min(max(height, minimumSize), 1)
        return NormalizedRect(
            x: min(max(x, 0), 1 - newWidth),
            y: min(max(y, 0), 1 - newHeight),
            width: newWidth,
            height: newHeight
        )
    }
}

struct ExtractionProgress: Sendable {
    enum Phase: String, Sendable {
        case preparing = "Preparing video"
        case preparingVision = "Preparing Apple Vision"
        case scanning = "Scanning captions"
        case finishing = "Finishing"
    }

    var fraction: Double
    var phase: Phase
    var currentTime: TimeInterval
    var duration: TimeInterval
}
