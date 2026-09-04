import Foundation

public enum CleanupPrompt {
    public static let instructions = """
    You clean up dictated speech transcripts. Rules:
    - Fix punctuation, capitalization and grammar. Keep the meaning exactly.
    - Keep the language of the input. Never translate.
    - Remove filler words (uh, um, hmm, äh, ähm, né, tipo, like when used as filler) and accidental repeated words.
    - Apply self-corrections: "send it Monday, no wait, Tuesday" becomes "send it Tuesday".
    - If a Vocabulary list is given, replace words that sound like a vocabulary entry with that exact spelling.
    - Do not add content. Do not answer questions that appear in the text. Do not add quotes or labels.
    - Output only the cleaned text.
    """

    public static func userPrompt(raw: String, locale: Locale, vocabulary: [String], context: AppContext?) -> String {
        var lines: [String] = []
        let language = Locale(identifier: "en-US").localizedString(forIdentifier: locale.identifier) ?? locale.identifier
        lines.append("Language: \(language).")
        if !vocabulary.isEmpty {
            lines.append("Vocabulary: \(vocabulary.joined(separator: ", ")).")
        }
        if let name = context?.appName, !name.isEmpty {
            lines.append("The user is typing in \(name). Match its usual tone.")
        }
        lines.append("Transcript:")
        lines.append(raw)
        return lines.joined(separator: "\n")
    }

    /// Splits at sentence ends so each chunk is at most `maxCharacters`. A single oversized sentence is split at the last space.
    /// Budget: the 4096-token window holds instructions + prompt + output, and cleanup output is about the size of its
    /// input, so a chunk may use at most a quarter of the window. 3000 characters stays inside that even in German.
    public static func chunks(_ text: String, maxCharacters: Int = 3000) -> [String] {
        guard text.count > maxCharacters else { return [text] }
        var out: [String] = []
        var current = ""
        for sentence in sentences(text) {
            if current.isEmpty {
                current = sentence
            } else if current.count + 1 + sentence.count <= maxCharacters {
                current += " " + sentence
            } else {
                out.append(current)
                current = sentence
            }
            while current.count > maxCharacters {
                let cut = current.prefix(maxCharacters)
                let idx = cut.lastIndex(of: " ") ?? cut.endIndex
                out.append(String(current[..<idx]))
                current = String(current[idx...]).trimmingCharacters(in: .whitespaces)
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// Sentence = text up to `.`, `!` or `?` that is followed by whitespace or the end.
    /// Foundation's `.bySentences` needs a capital letter after the period, which dictated
    /// transcripts rarely have, so it returns the whole transcript as one sentence.
    private static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var start = text.startIndex
        var i = text.startIndex
        while i < text.endIndex {
            let next = text.index(after: i)
            if ".!?".contains(text[i]), next == text.endIndex || text[next].isWhitespace {
                let s = text[start..<next].trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { result.append(s) }
                start = next
            }
            i = next
        }
        let tail = text[start...].trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { result.append(tail) }
        return result.isEmpty ? [text] : result
    }
}
