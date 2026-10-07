import Foundation

/// Removes sounds that are never words, before and after the cleanup model, so "uh" and "um"
/// cannot survive a model that skips its instructions on tidy text.
///
/// The lists are per language because a filler in one is a word in another: "um" is German for
/// "at" ("um zehn Uhr"), and "eh" is German for "anyway". "mm" is never listed: it is millimetres.
public enum FillerFilter {
    static let fillers: [String: Set<String>] = [
        "en": ["uh", "uhm", "um", "hm", "hmm"],
        "de": ["äh", "ähm", "öh", "hm"],
        "pt": ["ãh", "hum"],
    ]

    public static func apply(_ text: String, languageID: String) -> String {
        let language = String(languageID.prefix { $0 != "-" }).lowercased()
        guard let words = fillers[language], !words.isEmpty else { return text }
        let alternation = words.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        // The filler, the comma right after it, and the spaces after that. Word boundaries keep
        // "umbrella" and "hummus" whole.
        guard let regex = try? NSRegularExpression(
            pattern: "(?<![\\p{L}\\p{N}])(?:\(alternation))(?![\\p{L}\\p{N}]),?\\s*",
            options: .caseInsensitive) else { return text }
        let stripped = regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        // A removed filler can leave a comma with nothing after it ("So, um, we" → "So, we" is
        // fine, but "hello, um" → "hello, "), so trim the ends.
        return stripped.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",")))
    }
}
