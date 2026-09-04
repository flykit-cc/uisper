import Foundation
import FoundationModels
import os

@Generable
struct CleanedTranscript {
    @Guide(description: "The cleaned transcript text, nothing else.")
    var text: String
}

/// Cleans transcripts with Apple's on-device language model.
public final class FoundationModelsCleaner: TranscriptCleaner {
    private let log = Logger(subsystem: "cc.flykit.uisper", category: "cleanup")

    public init() {}

    /// nil when the model is usable; otherwise a one-line reason for the UI.
    public static var availabilityMessage: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "This Mac cannot run Apple Intelligence."
            case .appleIntelligenceNotEnabled: return "Apple Intelligence is off. Turn it on in System Settings."
            case .modelNotReady: return "The Apple Intelligence model is still downloading."
            @unknown default: return "Apple Intelligence is unavailable."
            }
        }
    }

    public func clean(_ raw: String, locale: Locale, vocabulary: [String], context: AppContext?) async throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        var pieces: [String] = []
        for chunk in CleanupPrompt.chunks(trimmed) {
            let session = LanguageModelSession(model: .default, instructions: CleanupPrompt.instructions)
            let prompt = CleanupPrompt.userPrompt(raw: chunk, locale: locale, vocabulary: vocabulary, context: context)
            let response = try await session.respond(
                to: prompt, generating: CleanedTranscript.self,
                options: GenerationOptions(sampling: .greedy))
            let piece = response.content.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { pieces.append(piece) }
        }
        let out = pieces.joined(separator: " ")
        log.debug("cleaned \(trimmed.count) → \(out.count) chars")
        return out
    }
}
