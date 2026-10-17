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

/// Answers each word-pick question from a table keyed by the spot phrase; unknown spots get "leave it".
actor FakeDecider: DecisionModel {
    var answers: [String: [Double]] = [:]
    var delay: Duration = .zero
    var error: Error?
    private(set) var questions: [(header: String, context: String, question: String, options: [String])] = []

    init(answers: [String: [Double]] = [:], delay: Duration = .zero, error: Error? = nil) {
        self.answers = answers; self.delay = delay; self.error = error
    }

    func decide(header: String, context: String, question: String, options: [String]) async throws -> [Double] {
        questions.append((header, context, question, options))
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
        let phrase = options[0].replacingOccurrences(of: ", as written", with: "")
        return answers[phrase] ?? [1] + Array(repeating: 0, count: options.count - 1)
    }
}
