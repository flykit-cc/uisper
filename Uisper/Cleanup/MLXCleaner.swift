import Foundation
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers
import UisperCore
import os

/// Cleans transcripts with the built-in model (Qwen3 4B, 4-bit) running on MLX.
/// Works on every Apple Silicon Mac, needs no Apple Intelligence, and does not share the
/// system model's queue with mediaanalysisd and friends.
actor MLXCleaner: TranscriptCleaner {
    struct NotDownloaded: Error {}

    private let directory: URL
    private let log = Logger(subsystem: "cc.flykit.uisper", category: "mlx")
    private var model: ModelContainer?
    private var loading: Task<ModelContainer, Error>?

    init(directory: URL) { self.directory = directory }

    /// Loads the model and runs one tiny generation so the first dictation pays neither the
    /// load (~0.5 s) nor the Metal kernel compile (~1 s). Safe to call repeatedly.
    func prewarm() async {
        do {
            let model = try await container()
            _ = try await Self.session(model, "Reply with OK.", maxTokens: 1).respond(to: "hi")
        } catch { log.error("prewarm failed: \(error.localizedDescription, privacy: .public)") }
    }

    /// A fresh session per call: no history, so nothing from the last dictation leaks in.
    private static func session(_ model: ModelContainer, _ instructions: String, maxTokens: Int = 1024) -> ChatSession {
        ChatSession(model, instructions: instructions,
                    generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0),
                    additionalContext: ["enable_thinking": false])
    }

    func clean(_ raw: String, locale: Locale, vocabulary: [String], context: AppContext?) async throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        // Throwing makes the session insert the raw text; blocking on a 2 GB download would not.
        guard ModelDownload.isComplete(directory) else { throw NotDownloaded() }
        let model = try await container()
        var pieces: [String] = []
        let instructions = CleanupPrompt.instructions(locale: locale, vocabulary: vocabulary, context: context)
        for chunk in CleanupPrompt.chunks(trimmed) {
            let started = ContinuousClock.now
            let piece = Self.stripThinking(try await Self.session(model, instructions).respond(to: chunk))
            log.info("cleaned \(chunk.count) chars in \(ContinuousClock.now - started, privacy: .public)")
            if !piece.isEmpty { pieces.append(piece) }
        }
        return pieces.joined(separator: " ")
    }

    private func container() async throws -> ModelContainer {
        if let model { return model }
        if let loading { return try await loading.value }
        let task = Task { [directory] in
            let started = ContinuousClock.now
            let m = try await loadModelContainer(from: directory, using: #huggingFaceTokenizerLoader())
            log.info("model loaded in \(ContinuousClock.now - started, privacy: .public)")
            return m
        }
        loading = task
        defer { loading = nil }
        let m = try await task.value
        model = m
        return m
    }

    /// Qwen3 sometimes emits an empty `<think></think>` block even with thinking off.
    static func stripThinking(_ s: String) -> String {
        var out = s
        while let open = out.range(of: "<think>"), let close = out.range(of: "</think>", range: open.upperBound..<out.endIndex) {
            out.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
