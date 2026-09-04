import AVFoundation
import Foundation
import Speech
import os

/// Apple's on-device SpeechAnalyzer/SpeechTranscriber (macOS 26).
public final class AppleSpeechEngine: SpeechEngine {
    public let id: EngineID = .apple
    private let contextualStrings: @Sendable () -> [String]
    private let log = Logger(subsystem: "cc.flykit.uisper", category: "apple-speech")

    public init(contextualStrings: @escaping @Sendable () -> [String] = { [] }) {
        self.contextualStrings = contextualStrings
    }

    public static func installedLocales() async -> [Locale] {
        await SpeechTranscriber.installedLocales
    }

    public func supports(_ locale: Locale) async -> Bool {
        await SpeechTranscriber.supportedLocale(equivalentTo: locale) != nil
    }

    public func prepare(locale: Locale) async throws {
        let normalized = try await normalized(locale)
        let transcriber = makeTranscriber(normalized)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            log.info("installing speech assets for \(normalized.identifier, privacy: .public)")
            try await request.downloadAndInstall()
        }
    }

    public func preferredFormat() async -> AVAudioFormat? {
        let t = makeTranscriber(Locale(identifier: "en-US"))
        return await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [t])
    }

    public func start(locale: Locale, audio: sending AsyncStream<AVAudioPCMBuffer>) -> AsyncThrowingStream<TranscriptUpdate, Error> {
        let contextual = contextualStrings()
        let (stream, continuation) = AsyncThrowingStream<TranscriptUpdate, Error>.makeStream()
        let (analyzerInput, builder) = AsyncStream<AnalyzerInput>.makeStream()

        // `audio` is `sending`, so it may be consumed by exactly one task, and that task has
        // to be spawned here at the top level of `start` where the value is still disconnected.
        // Hence the split: this task only re-packages buffers, the one below runs the analyzer.
        let feed = Task {
            for await buffer in audio { builder.yield(AnalyzerInput(buffer: buffer)) }
            builder.finish()
        }

        let task = Task {
            do {
                let normalized = try await self.normalized(locale)
                let transcriber = self.makeTranscriber(normalized)
                let analyzer = SpeechAnalyzer(modules: [transcriber])
                if !contextual.isEmpty {
                    let ctx = AnalysisContext()
                    ctx.contextualStrings = [.general: contextual]
                    try await analyzer.setContext(ctx)
                }
                let results = transcriber.results
                try await analyzer.start(inputSequence: analyzerInput)

                // Finalizing is what ends `results`, so it has to run alongside the drain below.
                async let finalized: Void = {
                    _ = await feed.result
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                }()

                for try await result in results {
                    let text = String(result.text.characters)
                    continuation.yield(TranscriptUpdate(text: text, isFinal: result.isFinal))
                }
                try await finalized
                continuation.finish()
            } catch {
                self.log.error("engine failed: \(error.localizedDescription, privacy: .public)")
                // Keep our own cases intact; only foreign errors get wrapped.
                let out = error as? SpeechEngineError ?? .engineFailed(error.localizedDescription)
                continuation.finish(throwing: out)
            }
        }
        continuation.onTermination = { _ in
            feed.cancel()
            task.cancel()
        }
        return stream
    }

    private func makeTranscriber(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: []
        )
    }

    private func normalized(_ locale: Locale) async throws -> Locale {
        guard let l = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw SpeechEngineError.unsupportedLocale(locale.identifier)
        }
        return l
    }
}
