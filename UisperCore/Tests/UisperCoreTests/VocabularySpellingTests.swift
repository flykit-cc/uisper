import Foundation
import Testing
@testable import UisperCore

struct VocabularySpellingTests {
    @Test func rejoinsASplitName() {
        #expect(VocabularySpelling.apply(["flykit"], to: "about the fly kit release") == "about the flykit release")
    }

    @Test func matchesRegardlessOfCaseAndUsesTheUsersSpelling() {
        #expect(VocabularySpelling.apply(["flykit"], to: "The Fly Kit release") == "The flykit release")
    }

    @Test func leavesTextAloneWhenNothingWasSplit() {
        let text = "the flykit release is fine"
        #expect(VocabularySpelling.apply(["flykit"], to: text) == text)
    }

    /// Word boundaries matter: the split must be two whole words, not part of longer ones.
    @Test func doesNotJoinAcrossLongerWords() {
        let text = "a butterfly kitchen"
        #expect(VocabularySpelling.apply(["flykit"], to: text) == text)
    }

    /// Short entries generate splits like "a pi" that would fire on ordinary speech.
    @Test func shortWordsAreNotRejoined() {
        let text = "give me a PI value"
        #expect(VocabularySpelling.apply(["API", "dsh"], to: text) == text)
    }

    @Test func multiWordEntriesAreLeftAlone() {
        let text = "we use Claude Code here"
        #expect(VocabularySpelling.apply(["Claude Code"], to: text) == text)
    }

    @Test func splitsCoverEveryInnerPosition() {
        #expect(VocabularySpelling.splits(of: "flykit") == ["fl ykit", "fly kit", "flyk it"])
    }

    // MARK: - Near misses

    private static let list = ["Claude Code", "Deepseek", "Deepseek Harness", "flykit", "Kaio", "dsh", "API"]

    private func fixed(_ text: String) -> String {
        VocabularySpelling.apply(Self.list, to: text)
    }

    @Test func fixesAMisheardTwoWordName() {
        #expect(fixed("I use clot code every day") == "I use Claude Code every day")
    }

    @Test func fixesAMisheardSingleWord() {
        #expect(fixed("we ship fly kid tonight") == "we ship flykit tonight")
    }

    @Test func correctsCasingToTheUsersSpelling() {
        #expect(fixed("open claude code now") == "open Claude Code now")
    }

    /// "Deepseek Harness" must win the whole phrase before "Deepseek" claims the first half.
    @Test func theLongestEntryWins() {
        #expect(fixed("run the deep seek harness") == "run the Deepseek Harness")
    }

    @Test func leavesUnrelatedTextAlone() {
        let text = "the cloud was grey and the code compiled"
        #expect(fixed(text) == text)
    }

    /// Short entries are one edit from ordinary words, which is how the acoustic version
    /// destroyed sentences. They are never fuzzy-matched.
    @Test func shortEntriesAreNeverFuzzyMatched() {
        let text = "put the dish in a pie and ask Cairo"
        #expect(fixed(text) == text)
    }

    @Test func punctuationAroundTheMatchSurvives() {
        #expect(fixed("yes, clot code, exactly.") == "yes, Claude Code, exactly.")
    }

    @Test func alreadyCorrectTextIsUntouched() {
        let text = "Claude Code and Deepseek and flykit"
        #expect(fixed(text) == text)
    }
}
