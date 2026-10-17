import Testing
@testable import UisperCore

struct SpotFinderTests {
    let vocab = ["Anthropic", "API", "Claude Code", "flykit", "honcho", "repo", "Quants", "Parakeet", "Qwen"]

    private func phrases(_ text: String) -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: SpotFinder.spots(in: text, vocabulary: vocab).map { ($0.phrase, $0.candidates) })
    }

    // The four misheard names from Kaio's live test on 2026-10-17.
    @Test func findsTheRealMisheardNames() {
        #expect(phrases("Can you open cloud code and check the flykit REPL?")["cloud code"]?.first == "Claude Code")
        #expect(phrases("read the logs from hancho.")["hancho"] == ["honcho"])
        #expect(phrases("Ask Antropic if it runs.")["Antropic"] == ["Anthropic"])
    }

    @Test func exactEntriesAreNotSpots() {
        #expect(phrases("Open honcho and the flykit repo.").isEmpty)
        #expect(phrases("Open Claude Code now").isEmpty)
    }

    @Test func commonWordsAloneAreNeverSpots() {
        // "Queen" is close to "Qwen" but is an ordinary word.
        #expect(phrases("the Queen 34B model").isEmpty)
    }

    @Test func ordinaryTextRaisesNothing() {
        #expect(phrases("Can you check it? Let's meet tomorrow and send the invoice.").isEmpty)
    }

    @Test func spotsComeInTextOrderAndNeverOverlap() {
        let spots = SpotFinder.spots(in: "ask cloud code about hancho", vocabulary: vocab)
        #expect(spots.map(\.phrase) == ["cloud code", "hancho"])
        #expect(!spots[0].range.overlaps(spots[1].range))
    }
}
