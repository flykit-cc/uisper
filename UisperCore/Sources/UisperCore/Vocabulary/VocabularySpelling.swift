import Foundation

/// Puts the user's own words back the way they spell them.
///
/// Two mistakes the speech engine makes with a name it does not know: it splits it ("flykit"
/// becomes "fly kit"), or it hears something close but wrong ("Claude Code" becomes "clot
/// code"). Asking the cleanup model to fix either does not work — on an already well-formed
/// transcript a 4B model does the removals it is told to and skips the rewrites.
///
/// So this is deterministic, and deliberately narrow: it can only ever produce a word the user
/// typed into their own vocabulary, it ignores short entries, and it demands a close match.
/// Acoustic biasing was tried instead and had to be removed — at the sound level a wrong guess
/// rewrites a whole clause, while here the worst case is one wrong word.
public enum VocabularySpelling {
    /// Both halves of a split must be at least this long, or "API" would rejoin "a PI".
    static let minPartLength = 2
    /// Entries shorter than this are never matched: at three or four characters "dsh" is one
    /// edit away from "dish" and "Kaio" from "Cairo".
    static let minEntryLength = 5
    /// How different a phrase may be and still be treated as the user's word. Measured against
    /// real mishearings: "clot code"/"Claude Code" is 0.36 and "fly kid"/"flykit" is 0.29, while
    /// ordinary phrases land at 0.40 and up ("deep work"/"Deepseek" 0.44, "the code" 0.45).
    /// The line sits in that gap. Deliberately caught on the way: "cloud code" (0.18) becomes
    /// "Claude Code" — nearer than the real mishearing, and almost always what was meant.
    static let maxEditRatio = 0.38

    /// `text` with the user's spelling restored wherever the engine split or misheard one of
    /// their words.
    public static func apply(_ vocabulary: [String], to text: String) -> String {
        nearMisses(vocabulary, in: splitWords(vocabulary, in: text))
    }

    // MARK: - Split words

    /// Rejoins a single vocabulary word the engine heard as two: "fly kit" → "flykit".
    static func splitWords(_ vocabulary: [String], in text: String) -> String {
        var out = text
        for word in vocabulary where word.count >= minEntryLength && !word.contains(" ") {
            for split in splits(of: word) {
                out = replace(split, with: word, in: out)
            }
        }
        return out
    }

    /// Every way the word could have been heard as two: "fly kit", "flyk it", and so on.
    static func splits(of word: String) -> [String] {
        let characters = Array(word)
        return (minPartLength...(characters.count - minPartLength)).map {
            String(characters[..<$0]) + " " + String(characters[$0...])
        }
    }

    /// Case-insensitive whole-word replacement. The word boundaries keep "fly kit" inside
    /// "butterfly kitchen" from being touched.
    private static func replace(_ split: String, with word: String, in text: String) -> String {
        guard let pattern = try? NSRegularExpression(
            pattern: "\\b" + NSRegularExpression.escapedPattern(for: split) + "\\b",
            options: .caseInsensitive) else { return text }
        return pattern.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: word)
    }

    // MARK: - Near misses

    /// Replaces a run of words that is nearly one of the user's entries with that entry.
    static func nearMisses(_ vocabulary: [String], in text: String) -> String {
        let words = wordRanges(in: text)
        guard !words.isEmpty else { return text }
        // Longest entries first: "Deepseek Harness" must win before "Deepseek" takes half of it.
        let entries = vocabulary
            .filter { $0.count >= minEntryLength }
            .sorted { $0.split(separator: " ").count > $1.split(separator: " ").count }

        var replacements: [(Range<String.Index>, String)] = []
        var claimed: [Range<String.Index>] = []
        for entry in entries {
            // The entry's own word count, one fewer for a name run together ("Claudecode"),
            // and one more for a single word split in two ("fly kid"). The split case is judged
            // separately, because adding a neighbour to a phrase keeps the ratio low enough to
            // swallow it: "Deepseek and" is only 0.33 away from "Deepseek".
            let own = entry.split(separator: " ").count
            let lengths = own == 1 ? [1, 2] : [own - 1, own]
            for length in lengths where length >= 1 && length <= words.count {
                for start in 0...(words.count - length) {
                    let span = words[start].lowerBound..<words[start + length - 1].upperBound
                    guard !claimed.contains(where: { $0.overlaps(span) }) else { continue }
                    let candidate = String(text[span])
                    // An exact match needs nothing; a case-only difference is still the user's
                    // spelling to restore ("claude code" → "Claude Code").
                    guard candidate != entry else { continue }
                    let matched = candidate.lowercased() == entry.lowercased()
                        || (length > own ? isSplitOf(candidate, entry)
                            : isNearMiss(candidate, entry) && !containsAnEntry(candidate, vocabulary))
                    guard matched else { continue }
                    replacements.append((span, entry))
                    claimed.append(span)
                }
            }
        }

        // Back to front, so the ranges taken from the original string stay valid.
        var out = text
        for (span, entry) in replacements.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
            out.replaceSubrange(span, with: entry)
        }
        return out
    }

    /// True when the candidate already holds one of the user's words, spelled right. Distance
    /// alone cannot see this: "Deepseek and" sits *closer* to "Deepseek Harness" (0.31) than the
    /// real mishearing "clot code" does to "Claude Code" (0.36), so a threshold either takes
    /// both or neither. What separates them is that one of them is already correct — and text
    /// the user spells the way they asked for is never something to overwrite.
    static func containsAnEntry(_ candidate: String, _ vocabulary: [String]) -> Bool {
        let words = wordRanges(in: candidate).map { candidate[$0].lowercased() }
        return vocabulary.contains { entry in
            let parts = entry.lowercased().split(separator: " ").map(String.init)
            guard !parts.isEmpty, parts.count <= words.count else { return false }
            return (0...(words.count - parts.count)).contains { start in
                Array(words[start..<(start + parts.count)]) == parts
            }
        }
    }

    /// A word split in two is all but identical once the space is gone, so this is judged much
    /// more strictly than a plain mishearing. Without that, any short neighbouring word gets
    /// absorbed: "Deepseek and" sits 0.33 from "Deepseek", well inside the normal tolerance.
    static func isSplitOf(_ candidate: String, _ entry: String) -> Bool {
        let joined = candidate.replacingOccurrences(of: " ", with: "")
        let longest = max(joined.count, entry.count)
        guard longest > 0 else { return false }
        let distance = CorrectionLearner.editDistance(joined.lowercased(), entry.lowercased())
        return Double(distance) / Double(longest) <= 0.2
    }

    static func isNearMiss(_ candidate: String, _ entry: String) -> Bool {
        let longest = max(candidate.count, entry.count)
        guard longest > 0 else { return false }
        let distance = CorrectionLearner.editDistance(candidate.lowercased(), entry.lowercased())
        return Double(distance) / Double(longest) <= maxEditRatio
    }

    /// The ranges of every word in the text, so a match can be swapped out without disturbing
    /// the punctuation around it.
    static func wordRanges(in text: String) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        var start: String.Index?
        for index in text.indices {
            if isWordCharacter(text[index]) {
                if start == nil { start = index }
            } else if let from = start {
                out.append(from..<index)
                start = nil
            }
        }
        if let from = start { out.append(from..<text.endIndex) }
        return out
    }

    private static func isWordCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "'" || c == "\u{2019}" || c == "-"
    }
}
