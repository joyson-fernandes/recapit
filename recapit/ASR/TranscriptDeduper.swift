import Foundation

final class TranscriptDeduper {
    private var accumulated: String = ""
    private let overlapWords: Int = 30

    @discardableResult
    func add(_ newText: String) -> String {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        if accumulated.isEmpty {
            accumulated = trimmed
            return accumulated
        }
        let prevTail = Array(accumulated.split(separator: " ").suffix(overlapWords))
        let newHead = Array(trimmed.split(separator: " ").prefix(overlapWords))
        let overlapLen = longestCommonSubsequenceTail(prevTail, newHead)
        if overlapLen == 0 {
            accumulated += " " + trimmed
        } else {
            let newWords = trimmed.split(separator: " ").dropFirst(overlapLen)
            if !newWords.isEmpty {
                accumulated += " " + newWords.joined(separator: " ")
            }
        }
        return accumulated
    }

    private func longestCommonSubsequenceTail<E: Equatable>(_ a: [E], _ b: [E]) -> Int {
        var best = 0
        let aLen = a.count
        let bLen = b.count
        guard aLen > 0 && bLen > 0 else { return 0 }
        for k in 1...min(aLen, bLen) {
            if Array(a.suffix(k)) == Array(b.prefix(k)) { best = k }
        }
        return best
    }
}
