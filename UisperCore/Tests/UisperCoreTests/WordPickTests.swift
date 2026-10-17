import Foundation
import Testing
@testable import UisperCore

struct WordPickTests {
    let vocab = ["Claude Code", "honcho", "Anthropic"]

    @Test func replacesASpotOnlyAboveTheThreshold() async {
        let model = FakeDecider(answers: ["cloud code": [0.15, 0.85], "hancho": [0.25, 0.75]])
        let out = await WordPick.apply("open cloud code and read hancho logs", vocabulary: vocab, model: model)
        #expect(out.text == "open Claude Code and read hancho logs")
        #expect(out.changes.map(\.spot) == ["cloud code"] && out.changes.map(\.word) == ["Claude Code"] && out.changes.map(\.p) == [0.85])
        #expect(out.asked == 2 && !out.timedOut)
    }

    @Test func neverActsOnOptionA() async {
        let model = FakeDecider(answers: ["cloud code": [0.99, 0.01]])
        #expect(await WordPick.apply("open cloud code", vocabulary: vocab, model: model).text == "open cloud code")
    }

    @Test func asksTheSpikesQuestionWithTheWholeShortText() async {
        let model = FakeDecider()
        _ = await WordPick.apply("open cloud code now", vocabulary: vocab, model: model).text
        let q = await model.questions
        #expect(q.count == 1)
        #expect(q[0].header == "This text comes from speech recognition, which sometimes mishears names. "
                + "Names and terms this speaker often says: Claude Code, honcho, Anthropic\n\n")
        #expect(q[0].context == "open cloud code now")
        #expect(q[0].question == "This text was transcribed from speech. Did the speaker say 'cloud code', or was it a mishearing of one of these?")
        #expect(q[0].options == ["cloud code, as written", "Claude Code"])
    }

    @Test func asksAllSpotsOfOneContextInOneCall() async {
        let model = FakeDecider()
        _ = await WordPick.apply("ask Antropic, cloud code and hancho", vocabulary: vocab, model: model).text
        #expect(await model.calls == 1)
        #expect(await model.questions.count == 3)
    }

    @Test func longTextAsksOncePerSentence() async {
        let filler = Array(repeating: "This sentence is only here to make the text long.", count: 12).joined(separator: " ")
        let model = FakeDecider()
        _ = await WordPick.apply("Open cloud code now. " + filler + " Then read hancho logs.", vocabulary: vocab, model: model).text
        #expect(await model.calls == 2)
        #expect(await model.questions.map(\.context) == ["Open cloud code now.", "Then read hancho logs."])
    }

    @Test func pastThirtyWordsOnlyTheSpotsSentenceIsContext() async {
        let text = "Then open cloud code now. " + Array(repeating: "This sentence has exactly six words.", count: 5).joined(separator: " ")
        let model = FakeDecider()
        _ = await WordPick.apply(text, vocabulary: vocab, model: model)
        #expect(await model.questions.first?.context == "Then open cloud code now.")
    }

    @Test func longTextUsesOnlyTheSpotsSentence() async {
        let filler = Array(repeating: "This sentence is only here to make the text long.", count: 12).joined(separator: " ")
        let model = FakeDecider()
        _ = await WordPick.apply(filler + " Then open cloud code now.", vocabulary: vocab, model: model).text
        #expect(await model.questions.first?.context == "Then open cloud code now.")
    }

    @Test func editsSeveralSpotsWithoutShiftingPositions() async {
        let model = FakeDecider(answers: ["cloud code": [0, 1], "hancho": [0, 1], "Antropic": [0, 1]])
        let out = await WordPick.apply("ask Antropic, cloud code and hancho", vocabulary: vocab, model: model).text
        #expect(out == "ask Anthropic, Claude Code and honcho")
    }

    @Test func asksAtMostThreeQuestions() async {
        let model = FakeDecider()
        _ = await WordPick.apply("hancho hancho hancho hancho hancho hancho", vocabulary: vocab, model: model).text
        #expect(await model.questions.count == WordPick.maxSpots)
    }

    @Test func overBudgetLeavesTheTextAloneAndReturnsInTime() async {
        let model = FakeDecider(answers: ["hancho": [0, 1]], delay: .seconds(2))
        let started = ContinuousClock.now
        let out = await WordPick.apply("hancho and hancho", vocabulary: vocab, model: model)
        #expect(out.text == "hancho and hancho" && out.timedOut && out.changes.isEmpty)
        #expect(ContinuousClock.now - started < .milliseconds(800))
    }

    @Test func aModelErrorLeavesTheTextAlone() async {
        let model = FakeDecider(error: CancellationError())
        #expect(await WordPick.apply("open cloud code", vocabulary: vocab, model: model).text == "open cloud code")
    }
}
