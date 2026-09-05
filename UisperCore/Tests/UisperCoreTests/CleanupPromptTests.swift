import Foundation
import Testing
@testable import UisperCore

struct CleanupPromptTests {
    @Test func instructionsIncludeLanguageVocabularyAndApp() {
        let p = CleanupPrompt.instructions(
            locale: Locale(identifier: "de-DE"),
            vocabulary: ["Zephyr", "FlyKit"],
            context: AppContext(bundleID: "com.apple.mail", appName: "Mail", windowTitle: nil)
        )
        #expect(p.contains("German"))
        #expect(p.contains("Zephyr, FlyKit"))
        #expect(p.contains("typing in Mail"))
        #expect(!p.contains("on screen"))
    }

    @Test func instructionsOmitEmptyVocabularyAndContext() {
        let p = CleanupPrompt.instructions(locale: Locale(identifier: "en-US"), vocabulary: [], context: nil)
        #expect(!p.contains("Spell these names"))
        #expect(!p.contains("typing in"))
    }

    @Test func instructionsQuoteScreenTextAsReference() {
        let p = CleanupPrompt.instructions(
            locale: Locale(identifier: "en-US"),
            vocabulary: [],
            context: AppContext(bundleID: "x", appName: "Slack", windowTitle: nil, surroundingText: "Hey Zephyr,")
        )
        #expect(p.contains("Never output it"))
        #expect(p.contains("\"\"\"\nHey Zephyr,\n\"\"\""))
    }

    @Test func shortTextIsOneChunk() {
        #expect(CleanupPrompt.chunks("one. two. three.") == ["one. two. three."])
    }

    @Test func longTextSplitsAtSentenceBoundaries() {
        let sentence = String(repeating: "word ", count: 20).trimmingCharacters(in: .whitespaces) + "."
        let text = Array(repeating: sentence, count: 10).joined(separator: " ")   // ~1030 chars
        let chunks = CleanupPrompt.chunks(text, maxCharacters: 300)
        #expect(chunks.count >= 4)
        #expect(chunks.allSatisfy { $0.count <= 300 && $0.hasSuffix(".") })
        #expect(chunks.joined(separator: " ") == text)
    }

    @Test func passthroughReturnsInput() async throws {
        let out = try await PassthroughCleaner().clean("raw", locale: Locale(identifier: "en-US"), vocabulary: [], context: nil)
        #expect(out == "raw")
    }
}
