import Foundation

enum Timecode {
    static func string(from seconds: TimeInterval, decimalSeparator: Character = ",") -> String {
        let milliseconds = max(0, Int((seconds * 1_000).rounded()))
        let hours = milliseconds / 3_600_000
        let minutes = (milliseconds / 60_000) % 60
        let secs = (milliseconds / 1_000) % 60
        let millis = milliseconds % 1_000
        return String(
            format: "%02d:%02d:%02d%@%03d",
            hours,
            minutes,
            secs,
            String(decimalSeparator),
            millis
        )
    }

    static func parse(_ value: String) -> TimeInterval? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let components = normalized.split(separator: ":")
        guard components.count == 3,
              let hours = Double(components[0]),
              let minutes = Double(components[1]),
              let seconds = Double(components[2]),
              hours >= 0,
              minutes >= 0, minutes < 60,
              seconds >= 0, seconds < 60 else {
            return nil
        }
        return hours * 3_600 + minutes * 60 + seconds
    }
}
