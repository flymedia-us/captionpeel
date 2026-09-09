import Foundation

enum TextSimilarity {
    static func score(_ lhs: String, _ rhs: String) -> Double {
        let a = normalized(lhs)
        let b = normalized(rhs)
        if a == b { return 1 }
        if a.isEmpty || b.isEmpty { return 0 }

        let left = Array(a)
        let right = Array(b)
        var previous = Array(0...right.count)

        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1] + Array(repeating: 0, count: right.count)
            for (rightIndex, rightCharacter) in right.enumerated() {
                let insertion = current[rightIndex] + 1
                let deletion = previous[rightIndex + 1] + 1
                let substitution = previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                current[rightIndex + 1] = min(insertion, deletion, substitution)
            }
            previous = current
        }

        let distance = previous[right.count]
        return 1 - Double(distance) / Double(max(left.count, right.count))
    }

    private static func normalized(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters)
    }
}
