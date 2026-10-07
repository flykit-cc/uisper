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

    // MARK: - Casing

    private static let list = ["Claude Code", "Deepseek", "Deepseek Harness", "flykit", "Kaio", "dsh", "API"]

    private func fixed(_ text: String) -> String {
        VocabularySpelling.apply(Self.list, to: text)
    }

    @Test func correctsCasingToTheUsersSpelling() {
        #expect(fixed("open claude code now") == "open Claude Code now")
    }

    @Test func leavesUnrelatedTextAlone() {
        let text = "the cloud was grey and the code compiled"
        #expect(fixed(text) == text)
    }

    @Test func punctuationAroundTheMatchSurvives() {
        #expect(fixed("yes, claude code, exactly.") == "yes, Claude Code, exactly.")
    }

    @Test func alreadyCorrectTextIsUntouched() {
        let text = "Claude Code and Deepseek and flykit"
        #expect(fixed(text) == text)
    }

    @Test func aNearbyWordIsNeverRewritten() {
        #expect(VocabularySpelling.apply(["horse", "Claude Code"], to: "the house uses cloud code")
                == "the house uses cloud code")
    }

    @Test func commonWordEntriesNeverRecase() {
        #expect(VocabularySpelling.apply(["its", "Read"], to: "Its fine, read it") == "Its fine, read it")
    }

    @Test func multiWordEntriesRecase() {
        #expect(VocabularySpelling.apply(["Claude Code"], to: "open claude code now") == "open Claude Code now")
    }

    /// Where entries overlap, the longer one keeps its spelling.
    @Test func theLongestEntryKeepsItsCasing() {
        #expect(VocabularySpelling.apply(["deepseek", "Deepseek Harness"], to: "run the deepseek harness")
                == "run the Deepseek Harness")
    }
}
