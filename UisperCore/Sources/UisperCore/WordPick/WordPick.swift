import Foundation
import NaturalLanguage

/// A model that answers multiple-choice questions about one text, with one probability per option.
/// Option A (index 0) is always "leave it as it is". The prompt's context is `header + context`;
/// they are separate so a model can keep its state after the header, which changes only with the vocabulary.
/// All questions share the context, so a model can answer them in one pass.
public protocol DecisionModel: Sendable {
    func decide(header: String, context: String, questions: [(question: String, options: [String])]) async throws -> [[Double]]
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

    /// Never takes longer than `budget`: past it the text goes out unchanged and the model's
    /// answer, when it comes, is dropped.
    public static func apply(_ text: String, vocabulary: [String], model: any DecisionModel) async -> String {
        let spots = Array(SpotFinder.spots(in: text, vocabulary: vocabulary).prefix(maxSpots))
        guard !spots.isEmpty else { return text }
        // Not a task group: it waits for every child, and a model pass already running cannot be cancelled.
        let (first, done) = AsyncStream.makeStream(of: String.self)
        let work = Task {
            done.yield(await pick(spots, in: text, header: header(vocabulary), model: model))
            done.finish()
        }
        let timer = Task {
            // Without a tolerance the system may wake this ~10% late.
            try? await Task.sleep(for: budget, tolerance: .milliseconds(1))
            done.finish()
        }
        defer { work.cancel(); timer.cancel() }
        for await out in first { return out }
        return text
    }

    static func pick(_ spots: [Spot], in text: String, header: String, model: any DecisionModel) async -> String {
        var groups: [(context: String, spots: [Spot])] = []
        for spot in spots {
            let c = context(for: spot, in: text)
            if let i = groups.firstIndex(where: { $0.context == c }) { groups[i].spots.append(spot) } else { groups.append((c, [spot])) }
        }
        var edits: [(Range<String.Index>, String)] = []
        for group in groups {
            let questions = group.spots.map { spot in
                (question: "This text was transcribed from speech. Did the speaker say '\(spot.phrase)', or was it a mishearing of one of these?",
                 options: ["\(spot.phrase), as written"] + spot.candidates)
            }
            guard let answers = try? await model.decide(header: header, context: group.context, questions: questions),
                  answers.count == questions.count else { continue }
            for (spot, p) in zip(group.spots, answers) {
                guard p.count == spot.candidates.count + 1,
                      let best = p.indices.max(by: { p[$0] < p[$1] }), best > 0, p[best] >= threshold else { continue }
                edits.append((spot.range, spot.candidates[best - 1]))
            }
        }
        var out = text
        // From the end, so earlier ranges stay valid.
        for (range, word) in edits.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
            out.replaceSubrange(range, with: word)
        }
        return out
    }

    public static func header(_ vocabulary: [String]) -> String {
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
