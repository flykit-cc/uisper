import Foundation

/// A stretch of text that is spelled close to a vocabulary entry, with the entries it may be.
public struct Spot: Equatable, Sendable {
    public let range: Range<String.Index>
    public let phrase: String
    public let candidates: [String]
}

/// Finds words the speech engine may have misheard as something close to one of the user's entries.
///
/// It only finds and never changes anything: whether "cloud code" means "Claude Code" depends on the
/// sentence, and that is the Decider's question (`WordPick`). A wrong spot costs one question; a wrong
/// swap rewrites a good word, which is why `VocabularySpelling` no longer swaps near misses.
// ponytail: edit distance only. The spike's Double Metaphone sound match added only PowerCat→Parakeet,
// which the model never fixed (kept at 0.99). Add sound matching when a missed name the model would fix needs it.
public enum SpotFinder {
    static let maxDistance = 0.34
    /// Shorter keys match too much by edit distance alone ("can" → "Qwen").
    static let minKeyLength = 4
    static let maxCandidates = 3

    public static func spots(in text: String, vocabulary: [String]) -> [Spot] {
        let words = text.ranges(of: /[A-Za-z0-9][A-Za-z0-9'-]*/)
        let entries = vocabulary.map { ($0, key($0)) }
        let exact = Set(entries.map(\.1))
        var found: [(distance: Double, length: Int, spot: Spot)] = []
        for n in [2, 1] where words.count >= n {
            for i in 0...(words.count - n) {
                let range = words[i].lowerBound..<words[i + n - 1].upperBound
                let phrase = String(text[range])
                let k = key(phrase)
                guard k.count >= minKeyLength, !exact.contains(k),
                      !words[i..<(i + n)].contains(where: { exact.contains(key(String(text[$0]))) }) else { continue }
                if n == 1, CommonWords.contains(phrase) { continue }
                let matches = entries
                    .map { (Double(distance(k, $0.1)) / Double(max(k.count, $0.1.count)), $0.0) }
                    .filter { $0.0 <= maxDistance }
                    .sorted { $0.0 < $1.0 }
                guard let best = matches.first else { continue }
                found.append((best.0, n, Spot(range: range, phrase: phrase, candidates: matches.prefix(maxCandidates).map(\.1))))
            }
        }
        // Closest match first; on a tie the longer phrase wins, so "cloud code" beats "code".
        var spots: [Spot] = []
        for f in found.sorted(by: { ($0.distance, -$0.length) < ($1.distance, -$1.length) })
        where !spots.contains(where: { $0.range.overlaps(f.spot.range) }) {
            spots.append(f.spot)
        }
        return spots.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    static func key(_ s: String) -> String {
        String(s.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0...b.count)
        for (i, ca) in a.enumerated() {
            var current = [i + 1]
            for (j, cb) in b.enumerated() {
                current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + (ca == cb ? 0 : 1)))
            }
            previous = current
        }
        return previous[b.count]
    }
}
