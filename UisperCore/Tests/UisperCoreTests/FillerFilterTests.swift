import Testing
@testable import UisperCore

struct FillerFilterTests {
    @Test func removesEnglishFillersWithTheirComma() {
        #expect(FillerFilter.apply("So, um, we could uh meet at ten", languageID: "en-US")
                == "So, we could meet at ten")
    }
    @Test func keepsTheGermanWordUm() {
        #expect(FillerFilter.apply("Wir treffen uns um zehn Uhr, äh, morgen", languageID: "de-DE")
                == "Wir treffen uns um zehn Uhr, morgen")
    }
    @Test func neverTouchesUnitsOrWordsContainingAFiller() {
        let text = "Use 5 mm screws, an umbrella and hummus"
        #expect(FillerFilter.apply(text, languageID: "en-US") == text)
    }
    @Test func keepsTheGermanWordEh() {
        let text = "Das ist eh klar"
        #expect(FillerFilter.apply(text, languageID: "de-DE") == text)
    }
    @Test func isCaseInsensitiveAndCleansSpacing() {
        #expect(FillerFilter.apply("Um, hello Hmm world", languageID: "en-GB") == "hello world")
    }
    @Test func unknownLanguageChangesNothing() {
        #expect(FillerFilter.apply("um uh", languageID: "fr-FR") == "um uh")
    }
    @Test func fillerOnlyInputBecomesEmpty() {
        #expect(FillerFilter.apply("uh, um", languageID: "en-US") == "")
    }
    @Test func noSpaceIsLeftBeforePunctuation() {
        #expect(FillerFilter.apply("That was great um. Thanks hmm, really", languageID: "en-US")
                == "That was great. Thanks really")
    }
}
