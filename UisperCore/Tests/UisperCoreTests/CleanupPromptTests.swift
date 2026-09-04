import Foundation
import Testing
@testable import UisperCore

struct CleanupPromptTests {
    @Test func promptIncludesLanguageVocabularyAndText() {
        let p = CleanupPrompt.userPrompt(
            raw: "hello uh world",
            locale: Locale(identifier: "de-DE"),
            vocabulary: ["Zephyr", "FlyKit"],
            context: AppContext(bundleID: "com.apple.mail", appName: "Mail", windowTitle: nil)
        )
        #expect(p.contains("German"))
        #expect(p.contains("Zephyr, FlyKit"))
        #expect(p.contains("Mail"))
        #expect(p.hasSuffix("hello uh world"))
    }

    @Test func promptOmitsEmptyVocabularyAndContext() {
        let p = CleanupPrompt.userPrompt(raw: "x", locale: Locale(identifier: "en-US"), vocabulary: [], context: nil)
        #expect(!p.contains("Vocabulary"))
        #expect(!p.contains("typing in"))
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
