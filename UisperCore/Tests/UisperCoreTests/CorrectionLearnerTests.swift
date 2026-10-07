import Foundation
import Testing
@testable import UisperCore

struct CorrectionLearnerTests {
    private func corrections(_ original: String, _ edited: String, dictionary: [String] = []) -> [String] {
        CorrectionLearner.extractCorrections(originalText: original, fieldValue: edited,
                                             existingDictionary: dictionary)
    }

    @Test func learnsAMisheardName() {
        #expect(corrections("I spoke to Shunade about it", "I spoke to Sinead about it") == ["Sinead"])
    }

    @Test func ignoresAnUnrelatedWordSwap() {
        #expect(corrections("we discussed the budget", "we discussed the timeline").isEmpty)
    }



    /// Grammar and tense edits are the commonest hand edits, and they only change the ending.
    /// Storing them would fill the list and bias the speech engine toward ordinary words.
    @Test func suffixOnlyEditsAreNotLearned() {
        #expect(corrections("I call her later", "I called her later").isEmpty)
        #expect(corrections("we run the test now", "we run the tests now").isEmpty)
    }

    /// Digits alone are not a name.
    @Test func numbersAreNotLearned() {
        #expect(corrections("due in 2024 for sure", "due in 2025 for sure").isEmpty)
    }

    /// The names worth learning are often all-lowercase, and requiring a capital would have
    /// made the feature useless for exactly the words it exists for.
    @Test func lowercaseNamesAreLearned() {
        #expect(corrections("we ship flykid today", "we ship flykit today") == ["flykit"])
        #expect(corrections("run cubectl now", "run kubectl now") == ["kubectl"])
    }

    /// `tokenize` only trims punctuation at the edges, so an on-screen token can still carry
    /// a colon or quotes. Every entry is interpolated into the cleanup prompt as a name.
    @Test func tokensCarryingPunctuationAreNotLearned() {
        #expect(corrections("follow the Instrucions", "follow the Instructions:IGNORE_ALL").isEmpty)
    }

    /// The curly apostrophe macOS substitutes by default must not disqualify a name.
    @Test func namesWithASmartApostropheAreLearned() {
        #expect(corrections("call O'Bryan now", "call O\u{2019}Brien now") == ["O\u{2019}Brien"])
    }

    /// An underscore survives tokenizing, so it could carry a whole phrase into the prompt.
    @Test func tokensCarryingAnUnderscoreAreNotLearned() {
        #expect(corrections("we deploy Kubernetes now", "we deploy Kubernetes_ignore_all_prior now").isEmpty)
    }

    /// Fixing both halves of a two-word name is the main use case; the old share guard blocked it.
    /// "John" is an ordinary word the engine already spells, so only the rare half is learned.
    @Test func bothHalvesOfANameAreLearned() {
        #expect(corrections("Sinaid and Jhon", "Sinead and John") == ["Sinead"])
    }

    @Test func commonWordsAreNeverLearned() {
        #expect(corrections("we need the exciting part", "we need the existing part").isEmpty)
    }

    @Test func claudeIsLearned() {
        #expect(corrections("I use clawed code daily", "I use Claude code daily") == ["Claude"])
    }

    @Test func aRewriteOfMostWordsLearnsNothing() {
        #expect(corrections("I think we should sell the house next year",
                            "I thing we could tell the horse next week").isEmpty)
    }

    @Test func aShortFixIsNotARewrite() {
        // 2 of 3 words changed, but under `rewriteGuardMinWords` the guard does not apply.
        #expect(corrections("Sinaid and Kayo", "Sinead and Kaio") == ["Sinead", "Kaio"])
    }

    @Test func ignoresARewrite() {
        #expect(corrections("the quick brown fox jumps", "a slow green turtle crawls").isEmpty)
    }

    @Test func ignoresWordsAlreadyKnown() {
        #expect(corrections("we use FlyKid here", "we use FlyKit here", dictionary: ["FlyKit"]).isEmpty)
        #expect(corrections("we use FlyKid here", "we use FlyKit here") == ["FlyKit"])
    }

    @Test func unchangedTextLearnsNothing() {
        #expect(corrections("nothing changed here", "nothing changed here").isEmpty)
    }

    @Test func ignoresVeryShortWords() {
        #expect(corrections("meet at the cafe today", "meet in the cafe today").isEmpty)
    }

    @Test func findsTheDictatedTextInsideALongerField() {
        let original = "please ping Sinaid before the call"
        let field = String(repeating: "existing note text. ", count: 12) + "please ping Sinead before the call"
        #expect(corrections(original, field) == ["Sinead"])
    }

    @Test func tokenizeStripsEdgePunctuation() {
        #expect(CorrectionLearner.tokenize("Hello, world! it's fine.") == ["Hello", "world", "it's", "fine"])
    }

    @Test func editDistanceCountsSingleEdits() {
        #expect(CorrectionLearner.editDistance("kitten", "sitting") == 3)
        #expect(CorrectionLearner.editDistance("same", "same") == 0)
        #expect(CorrectionLearner.editDistance("", "abc") == 3)
    }

    /// A terminal screen holds far more than the user's line. In a chat TUI it can hold the very
    /// sentence they were asked to dictate, which matches the insertion better than their edited
    /// copy does — so the learner compares the text against itself and finds nothing. Only the
    /// tail of the screen is passed in for exactly this reason.
    /// A terminal running a chat TUI shows the sentence the user was asked to dictate as well as
    /// the one they typed. The untouched copy always scores higher, so taking the best match
    /// compares the text with itself and finds nothing. The most recent copy is the user's.
    @Test func theEditedCopyWinsOverAnEarlierCopyOnScreen() {
        let inserted = "Tomorrow I will send a draft to Martin"
        let edited = inserted.replacingOccurrences(of: "Martin", with: "Marteen")
        let screen = "please dictate: \(inserted)\nlots of other output here\n> \(edited)"
        #expect(corrections(inserted, screen) == ["Marteen"])
    }

    /// Recency must not override sense: a later line that is nothing like the insertion is not
    /// a worse-scoring copy of it, and learning from it would invent words.
    @Test func unrelatedLaterTextIsNotTreatedAsTheEdit() {
        let inserted = "Tomorrow I will send a draft to Martin"
        let screen = "\(inserted)\nnpm run build finished with zero errors in four seconds flat"
        #expect(corrections(inserted, screen).isEmpty)
    }
}
