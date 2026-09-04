import AVFoundation
import Foundation
import Observation
import os

public enum SessionState: Sendable, Equatable {
    case idle
    case listening(text: String, volatile: String)
    case polishing(text: String)
    case inserted(result: InsertionResult)
    case error(String)
}

@MainActor
public protocol AudioSource: AnyObject {
    var level: Float { get }
    /// `sending`: the stream carries non-Sendable buffers and is handed straight to the engine.
    func start(targetFormat: AVAudioFormat?) throws -> sending AsyncStream<AVAudioPCMBuffer>
    func stop()
}

extension AudioCapture: AudioSource {}

/// The dictation state machine. One instance per app.
@MainActor
@Observable
public final class DictationSession {
    public private(set) var state: SessionState = .idle
    public var audioLevel: Float { audio.level }

    private let engine: SpeechEngine
    private let cleaner: TranscriptCleaner
    private let inserter: TextInserting
    private let audio: AudioSource
    private let settings: SettingsStore
    private let vocabulary: VocabularyStore
    private let contextProvider: @MainActor () -> AppContext?
    private let log = Logger(subsystem: "cc.flykit.uisper", category: "session")

    private var accumulator = TranscriptAccumulator()
    private var engineTask: Task<String, Error>?
    private var pressedAt: ContinuousClock.Instant?
    private var resetTask: Task<Void, Never>?
    /// Set once the user has let go: stops a slow engine task from opening the mic afterwards.
    private var stopRequested = false

    private static let accidentalTap: Duration = .milliseconds(300)

    public init(
        engine: SpeechEngine,
        cleaner: TranscriptCleaner,
        inserter: TextInserting,
        audio: AudioSource,
        settings: SettingsStore,
        vocabulary: VocabularyStore,
        contextProvider: @escaping @MainActor () -> AppContext? = { nil }
    ) {
        self.engine = engine
        self.cleaner = cleaner
        self.inserter = inserter
        self.audio = audio
        self.settings = settings
        self.vocabulary = vocabulary
        self.contextProvider = contextProvider
    }

    public func handle(_ event: HotkeyEvent) {
        switch (event, settings.mode) {
        case (.pressed, .hold):
            startListening()
        case (.released, .hold):
            finishListening()
        case (.pressed, .toggle):
            if case .listening = state { finishListening() } else { startListening() }
        case (.released, .toggle):
            break
        case (.cancelled, _):
            cancel()
        }
    }

    public func cancel() {
        engineTask?.cancel()
        engineTask = nil
        stopRequested = true
        audio.stop()
        accumulator = TranscriptAccumulator()
        pressedAt = nil
        state = .idle
    }

    // MARK: - Flow

    private func startListening() {
        guard state == .idle || isTransient(state) else { return }
        resetTask?.cancel()
        accumulator = TranscriptAccumulator()
        pressedAt = .now
        stopRequested = false
        state = .listening(text: "", volatile: "")
        let locale = settings.locale
        engineTask = Task { [weak self] in
            guard let self else { return "" }
            try await engine.prepare(locale: locale)
            let format = await engine.preferredFormat()
            // Last chance to bail: past this line the mic is live and only `audio.stop()`
            // closes it, so never open it for a press the user has already ended.
            try Task.checkCancellation()
            guard !stopRequested else { return accumulator.full }
            let stream = try audio.start(targetFormat: format)
            for try await update in engine.start(locale: locale, audio: stream) {
                try Task.checkCancellation()
                accumulator.apply(text: update.text, isFinal: update.isFinal)
                if case .listening = state {
                    state = .listening(text: accumulator.finalized, volatile: accumulator.volatile)
                }
            }
            return accumulator.full
        }
    }

    private func finishListening() {
        guard case .listening = state, let engineTask else { return }
        if let pressedAt, ContinuousClock.now - pressedAt < Self.accidentalTap {
            cancel()
            return
        }
        stopRequested = true
        audio.stop()
        state = .polishing(text: accumulator.full)
        let locale = settings.locale
        let words = vocabulary.words
        let context = contextProvider()
        let cleanupOn = settings.cleanupEnabled
        Task { [weak self] in
            guard let self else { return }
            do {
                let raw = try await engineTask.value
                self.engineTask = nil
                guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    fail("Nothing heard."); return
                }
                var text = raw
                if cleanupOn {
                    do { text = try await cleaner.clean(raw, locale: locale, vocabulary: words, context: context) }
                    catch { log.error("cleanup failed, inserting raw: \(error.localizedDescription, privacy: .public)") }
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { text = raw }
                }
                let result = await inserter.insert(text)
                state = .inserted(result: result)
                scheduleIdle(after: { if case .copiedOnly = result { return .seconds(2) } else { return .milliseconds(400) } }())
            } catch is CancellationError {
                state = .idle
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    private func fail(_ message: String) {
        log.error("\(message, privacy: .public)")
        engineTask = nil
        state = .error(message)
        scheduleIdle(after: .seconds(2))
    }

    private func scheduleIdle(after delay: Duration) {
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, isTransient(state) else { return }
            state = .idle
        }
    }

    private func isTransient(_ s: SessionState) -> Bool {
        switch s {
        case .inserted, .error: return true
        default: return false
        }
    }
}
