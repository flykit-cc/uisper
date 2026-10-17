import Foundation
import Testing
@testable import UisperCore

struct WordPickTests {
    let vocab = ["Claude Code", "honcho", "Anthropic"]

    @Test func replacesASpotOnlyAboveTheThreshold() async {
        let model = FakeDecider(answers: ["cloud code": [0.02, 0.98], "hancho": [0.10, 0.90]])
        let out = await WordPick.apply("open cloud code and read hancho logs", vocabulary: vocab, model: model)
        #expect(out == "open Claude Code and read hancho logs")
    }

    @Test func neverActsOnOptionA() async {
        let model = FakeDecider(answers: ["cloud code": [0.99, 0.01]])
        #expect(await WordPick.apply("open cloud code", vocabulary: vocab, model: model) == "open cloud code")
    }

    @Test func asksTheSpikesQuestionWithTheWholeShortText() async {
        let model = FakeDecider()
        _ = await WordPick.apply("open cloud code now", vocabulary: vocab, model: model)
        let q = await model.questions
        #expect(q.count == 1)
        #expect(q[0].context == "open cloud code now")
        #expect(q[0].question == "In this sentence, what did the speaker mean by 'cloud code'?")
        #expect(q[0].options == ["cloud code, as written", "Claude Code"])
    }

    @Test func longTextUsesOnlyTheSpotsSentence() async {
        let filler = Array(repeating: "This sentence is only here to make the text long.", count: 12).joined(separator: " ")
        let model = FakeDecider()
        _ = await WordPick.apply(filler + " Then open cloud code now.", vocabulary: vocab, model: model)
        #expect(await model.questions.first?.context == "Then open cloud code now.")
    }

    @Test func editsSeveralSpotsWithoutShiftingPositions() async {
        let model = FakeDecider(answers: ["cloud code": [0, 1], "hancho": [0, 1], "Antropic": [0, 1]])
        let out = await WordPick.apply("ask Antropic, cloud code and hancho", vocabulary: vocab, model: model)
        #expect(out == "ask Anthropic, Claude Code and honcho")
    }

    @Test func asksAtMostFourQuestions() async {
        let model = FakeDecider()
        _ = await WordPick.apply("hancho hancho hancho hancho hancho hancho", vocabulary: vocab, model: model)
        #expect(await model.questions.count == WordPick.maxSpots)
    }

    @Test func stopsAskingOnceTheBudgetIsSpent() async {
        let model = FakeDecider(answers: ["hancho": [0, 1]], delay: .milliseconds(300))
        let started = ContinuousClock.now
        let out = await WordPick.apply("hancho and hancho and hancho", vocabulary: vocab, model: model)
        #expect(await model.questions.count == 2)          // 0 ms and 300 ms start; 600 ms does not
        #expect(out == "honcho and honcho and hancho")
        #expect(ContinuousClock.now - started < .milliseconds(800))
    }

    @Test func aModelErrorLeavesTheTextAlone() async {
        let model = FakeDecider(error: CancellationError())
        #expect(await WordPick.apply("open cloud code", vocabulary: vocab, model: model) == "open cloud code")
    }
}
