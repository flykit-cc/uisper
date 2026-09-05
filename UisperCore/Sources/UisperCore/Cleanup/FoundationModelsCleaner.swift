import Foundation
import FoundationModels
import os

@Generable
struct CleanedTranscript {
    @Guide(description: "The cleaned transcript text, nothing else.")
    var text: String
}

/// Cleans transcripts with Apple's on-device language model.
public actor FoundationModelsCleaner: TranscriptCleaner {
    private let log = Logger(subsystem: "cc.flykit.uisper", category: "cleanup")

    public init() {
        if Self.availabilityMessage == nil { Self.makeSession().prewarm() }
    }

    private static func makeSession(instructions: String = "") -> LanguageModelSession {
        LanguageModelSession(model: .default, instructions: instructions)
    }

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
        let instructions = CleanupPrompt.instructions(locale: locale, vocabulary: vocabulary, context: context)
        for chunk in CleanupPrompt.chunks(trimmed) {
            // A fresh session per chunk: a session accumulates its transcript and would eventually overflow.
            let session = Self.makeSession(instructions: instructions)
            let response = try await session.respond(
                to: chunk, generating: CleanedTranscript.self,
                options: GenerationOptions(sampling: .greedy))
            let piece = response.content.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { pieces.append(piece) }
        }
        let out = pieces.joined(separator: " ")
        log.debug("cleaned \(trimmed.count) → \(out.count) chars")
        return out
    }
}
