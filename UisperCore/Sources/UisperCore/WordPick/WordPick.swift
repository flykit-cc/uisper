import Foundation
import NaturalLanguage

/// A model that answers a multiple-choice question about a text with one probability per option.
/// Option A (index 0) is always "leave it as it is". The prompt's context is `header + context`;
/// they are separate so a model can keep its state after the header, which changes only with the vocabulary.
public protocol DecisionModel: Sendable {
    func decide(header: String, context: String, question: String, options: [String]) async throws -> [Double]
}

/// Fixes misheard vocabulary words: for each spot the finder raises, asks the model whether the
/// speaker meant one of the user's entries, and swaps only when it is very sure.
///
/// The prompt is the 2026-10-17 prompt test's "variant 6": the vocabulary line plus a question about
/// mishearing. The plain "what did the speaker mean" question could not tell "a quant fund" (keep) from
/// the real fixes on a short dictation; this one gives real fixes 0.94-0.97 and that near miss 0.40-0.55.
public enum WordPick {
    public static let threshold = 0.90
    public static let maxSpots = 3
    public static let budget: Duration = .milliseconds(500)
    /// Above this the whole text as context costs more than the budget allows (spike: 211 words, 4 spots, 0.63 s).
    static let wholeTextWords = 100

    public static func apply(_ text: String, vocabulary: [String], model: any DecisionModel,
                             now: @Sendable () -> ContinuousClock.Instant = { .now }) async -> String {
        let started = now()
        var edits: [(Range<String.Index>, String)] = []
        for spot in SpotFinder.spots(in: text, vocabulary: vocabulary).prefix(maxSpots) {
            // ponytail: checked between questions, so one slow answer can overrun by its own length (~90 ms).
            guard now() - started < budget else { break }
            let options = ["\(spot.phrase), as written"] + spot.candidates
            guard let p = try? await model.decide(
                    header: header(vocabulary),
                    context: context(for: spot, in: text),
                    question: "This text was transcribed from speech. Did the speaker say '\(spot.phrase)', or was it a mishearing of one of these?",
                    options: options),
                  p.count == options.count,
                  let best = p.indices.max(by: { p[$0] < p[$1] }), best > 0, p[best] >= threshold
            else { continue }
            edits.append((spot.range, spot.candidates[best - 1]))
        }
        var out = text
        // From the end, so earlier ranges stay valid.
        for (range, word) in edits.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
            out.replaceSubrange(range, with: word)
        }
        return out
    }

    static func header(_ vocabulary: [String]) -> String {
        "This text comes from speech recognition, which sometimes mishears names. Names and terms this speaker often says: "
            + vocabulary.joined(separator: ", ") + "\n\n"
    }

    static func context(for spot: Spot, in text: String) -> String {
        guard text.split(whereSeparator: \.isWhitespace).count > wholeTextWords else { return text }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        let sentence = tokenizer.tokenRange(at: spot.range.lowerBound)
        return String(text[sentence]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
