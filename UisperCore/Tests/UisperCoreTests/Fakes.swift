import AVFoundation
import Foundation
@testable import UisperCore

/// Emits a scripted list of updates once the audio stream finishes.
final class FakeSpeechEngine: SpeechEngine, @unchecked Sendable {
    let id: EngineID = .apple
    var script: [TranscriptUpdate]
    var prepareError: Error?
    var startedLocales: [Locale] = []

    init(script: [TranscriptUpdate]) { self.script = script }

    func supports(_ locale: Locale) async -> Bool { true }
    func prepare(locale: Locale) async throws { if let prepareError { throw prepareError } }
    func preferredFormat() async -> AVAudioFormat? { nil }

    func start(locale: Locale, audio: sending AsyncStream<AVAudioPCMBuffer>) -> AsyncThrowingStream<TranscriptUpdate, Error> {
        startedLocales.append(locale)
        let script = self.script
        let (stream, continuation) = AsyncThrowingStream<TranscriptUpdate, Error>.makeStream()
        Task {
            for await _ in audio { }          // drain until the session finishes audio
            for u in script { continuation.yield(u) }
            continuation.finish()
        }
        return stream
    }
}

final class FakeCleaner: TranscriptCleaner, @unchecked Sendable {
    var transform: @Sendable (String) -> String = { "CLEAN(" + $0 + ")" }
    var error: Error?
    var calls: [(raw: String, vocabulary: [String])] = []

    func clean(_ raw: String, locale: Locale, vocabulary: [String], context: AppContext?) async throws -> String {
        calls.append((raw, vocabulary))
        if let error { throw error }
        return transform(raw)
    }
}

@MainActor
final class FakeInserter: TextInserting {
    var inserted: [String] = []
    var result: InsertionResult = .inserted
    func insert(_ text: String) async -> InsertionResult {
        inserted.append(text)
        return result
    }
}
