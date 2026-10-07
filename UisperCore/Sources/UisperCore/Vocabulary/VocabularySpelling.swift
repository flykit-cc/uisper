import Foundation

/// Puts the user's own words back the way they spell them.
///
/// It does two things only: it rejoins a word the speech engine split ("fly kit" → "flykit"),
/// and it restores the exact spelling of an entry the text already contains ("claude code" →
/// "Claude Code"). Asking the cleanup model to do either does not work: on an already
/// well-formed transcript a 4B model does the removals it is told to and skips the rewrites.
///
/// It never swaps a different word in, however close. One bad learned entry would otherwise
/// rewrite good words in every dictation (2026-10-07: the entry "horse" turned "house" into
/// "horse"). Misheard words are the Decider word pick's job (spec Part B).
public enum VocabularySpelling {
    /// Both halves of a split must be at least this long, or "API" would rejoin "a PI".
    static let minPartLength = 2
    /// Entries shorter than this are never rejoined: their splits ("a pi") are ordinary speech.
    static let minEntryLength = 5
    /// Single-word entries shorter than this never recase anything: "it" or "Al" would touch
    /// half the sentences.
    static let minCasingLength = 3

    /// `text` with split words rejoined and the user's spelling of their entries restored.
    public static func apply(_ vocabulary: [String], to text: String) -> String {
        restoreCasing(vocabulary, in: splitWords(vocabulary, in: text))
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
        // Escaped, because a typed entry may hold "$" or a backslash, which a template would expand.
        return pattern.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text),
            withTemplate: NSRegularExpression.escapedTemplate(for: word))
    }

    // MARK: - Casing

    /// Rewrites every whole-word occurrence of an entry in the entry's own spelling. A common
    /// word as an entry ("its", "Read") is skipped, so a junk entry cannot recase a sentence.
    /// Shortest first, so a longer entry has the last word where they overlap: "Deepseek
    /// Harness" keeps its casing even if "deepseek" is also listed.
    static func restoreCasing(_ vocabulary: [String], in text: String) -> String {
        vocabulary
            .filter { $0.contains(" ") || ($0.count >= minCasingLength && !CommonWords.contains($0)) }
            .sorted { $0.count < $1.count }
            .reduce(text) { out, entry in replace(entry, with: entry, in: out) }
    }
}
