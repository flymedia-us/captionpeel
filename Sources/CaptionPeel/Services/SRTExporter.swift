import Foundation

enum SRTExporter {
    static func render(_ cues: [CaptionCue]) -> String {
        cues
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
            }
            .enumerated()
            .map { index, cue in
                let cleanText = cue.text
                    .replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let start = max(0, cue.start)
                let end = max(start + 0.001, cue.end)
                return """
                \(index + 1)
                \(Timecode.string(from: start)) --> \(Timecode.string(from: end))
                \(cleanText)
                """
            }
            .joined(separator: "\n\n") + (cues.isEmpty ? "" : "\n")
    }

    static func write(_ cues: [CaptionCue], to url: URL) throws {
        try render(cues).write(to: url, atomically: true, encoding: .utf8)
    }
}
