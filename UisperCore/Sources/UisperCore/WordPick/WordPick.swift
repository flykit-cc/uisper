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
/// speaker meant one of the user's entries, and swaps only when it is sure enough.
///
/// The prompt is the 2026-10-17 prompt test's "variant 6": the vocabulary line plus a question about
/// mishearing. The plain "what did the speaker mean" question could not tell "a quant fund" (keep) from
/// the real fixes on a short dictation. With Kaio's 30-entry list this one gives cloud code 0.84-0.90,
/// hancho and Antropic 0.97, and keeps quant at 0.22 and Enzo at 0.43.
public enum WordPick {
    /// Set from about 22 cases only; re-check against the debug log after a week of use.
    public static let threshold = 0.80
    public static let maxSpots = 3
    public static let budget: Duration = .milliseconds(500)
    /// Past this the whole text as context does not fit the budget on an M1 Max (59 words, 3 spots: 0.54 s).
    static let wholeTextWords = 30

    public struct Outcome: Sendable {
        public var text: String
        public var changes: [(spot: String, word: String, p: Double)] = []
        public var asked = 0
        public var timedOut = false
    }

    /// Never takes longer than `budget`: past it the text goes out unchanged and the model's
    /// answer, when it comes, is dropped.
    public static func apply(_ text: String, vocabulary: [String], model: any DecisionModel) async -> Outcome {
        let spots = Array(SpotFinder.spots(in: text, vocabulary: vocabulary).prefix(maxSpots))
        guard !spots.isEmpty else { return Outcome(text: text) }
        // Not a task group: it waits for every child, and a model pass already running cannot be cancelled.
        let (first, done) = AsyncStream.makeStream(of: Outcome.self)
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
        return Outcome(text: text, asked: spots.count, timedOut: true)
    }

    static func pick(_ spots: [Spot], in text: String, header: String, model: any DecisionModel) async -> Outcome {
        var groups: [(context: String, spots: [Spot])] = []
        for spot in spots {
            let c = context(for: spot, in: text)
            if let i = groups.firstIndex(where: { $0.context == c }) { groups[i].spots.append(spot) } else { groups.append((c, [spot])) }
        }
        var edits: [(spot: Spot, word: String, p: Double)] = []
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
                edits.append((spot, spot.candidates[best - 1], p[best]))
            }
        }
        var out = text
        // From the end, so earlier ranges stay valid.
        for edit in edits.sorted(by: { $0.spot.range.lowerBound > $1.spot.range.lowerBound }) {
            out.replaceSubrange(edit.spot.range, with: edit.word)
        }
        return Outcome(text: out, changes: edits.map { ($0.spot.phrase, $0.word, $0.p) }, asked: spots.count)
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
