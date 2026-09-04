import Testing
@testable import UisperCore

struct TranscriptAccumulatorTests {
    @Test func volatileReplacesVolatile() {
        var a = TranscriptAccumulator()
        #expect(a.apply(text: "hel", isFinal: false) == "hel")
        #expect(a.apply(text: "hello wor", isFinal: false) == "hello wor")
        #expect(a.finalized == "")
        #expect(a.volatile == "hello wor")
    }

    @Test func finalAppendsAndClearsVolatile() {
        var a = TranscriptAccumulator()
        _ = a.apply(text: "hello wor", isFinal: false)
        #expect(a.apply(text: "hello world", isFinal: true) == "hello world")
        #expect(a.volatile == "")
        #expect(a.apply(text: "it is", isFinal: false) == "hello world it is")
        #expect(a.apply(text: "it is me", isFinal: true) == "hello world it is me")
    }

    @Test func joinsWithSingleSpaceAndTrims() {
        var a = TranscriptAccumulator()
        _ = a.apply(text: "  one ", isFinal: true)
        _ = a.apply(text: " two  ", isFinal: true)
        #expect(a.full == "one two")
    }
}
