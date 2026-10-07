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

    private let engines: [EngineID: any SpeechEngine]
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
    private var maxDurationTask: Task<Void, Never>?
    /// Set once the user has let go: stops a slow engine task from opening the mic afterwards.
    private var stopRequested = false
    /// What the last dictation inserted, and where, so the next one can see what the user fixed.
    private var lastInsertion: (text: String, bundleID: String?)?

    private static let accidentalTap: Duration = .milliseconds(300)
    /// Toggle mode has nothing to end a dictation the user walked away from, and the batch
    /// engines hold every sample until it ends. Finish rather than cancel, so the words spoken
    /// so far are still inserted.
    static let maxDictation: Duration = .seconds(600)

    public init(
        engines: [EngineID: any SpeechEngine],
        cleaner: TranscriptCleaner,
        inserter: TextInserting,
        audio: AudioSource,
        settings: SettingsStore,
        vocabulary: VocabularyStore,
        contextProvider: @escaping @MainActor () -> AppContext? = { nil }
    ) {
        self.engines = engines
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

    /// The engine picked in Settings, falling back to Apple when it is not in this build.
    /// Read once per dictation: `prepare`, `preferredFormat` and `start` must agree, or a
    /// mid-dictation switch could feed one engine's audio format to another.
    private var engine: any SpeechEngine {
        engines[settings.engine] ?? engines[.apple] ?? engines.values.first!
    }

    /// Downloads and loads whatever the chosen engine needs, so the first hotkey press is not
    /// the thing that waits on it.
    public func prepareEngine(locale: Locale) async throws {
        try await engine.prepare(locale: locale)
    }

    /// `prepare` on a cold engine is a model download, and a press during it would otherwise sit
    /// in `.polishing` for its whole length and then report "Nothing heard.", swallowing every
    /// press in between. Give up quickly instead and say why; the download itself keeps running
    /// inside the engine, so a later press finds it ready.
    private static func prepare(_ engine: any SpeechEngine, locale: Locale) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await engine.prepare(locale: locale) }
            group.addTask {
                try await Task.sleep(for: .seconds(2))
                throw SpeechEngineError.assetsMissing(locale.identifier)
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    public func cancel() {
        maxDurationTask?.cancel()
        maxDurationTask = nil
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
        maxDurationTask?.cancel()
        maxDurationTask = Task { [weak self] in
            try? await Task.sleep(for: Self.maxDictation)
            guard !Task.isCancelled, let self, case .listening = state else { return }
            log.info("dictation hit the \(Self.maxDictation, privacy: .public) limit, finishing")
            finishListening()
        }
        let locale = settings.locale
        let engine = self.engine
        engineTask = Task { [weak self] in
            guard let self else { return "" }
            try await Self.prepare(engine, locale: locale)
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
        maxDurationTask?.cancel()
        maxDurationTask = nil
        stopRequested = true
        audio.stop()
        state = .polishing(text: accumulator.full)
        let locale = settings.locale
        let cleanupOn = settings.cleanupEnabled
        Task { [weak self] in
            guard let self else { return }
            // Read inside the task, not above: `finishListening` runs inside the CGEvent tap
            // callback, and `contextProvider` makes Accessibility calls that can block on a
            // wedged app. A slow tap callback gets the tap disabled by the system.
            // Only the cleaner uses the context, so with cleanup off nothing on screen is read.
            let context = cleanupOn ? contextProvider() : nil
            await learnCorrections(from: context)
            let words = vocabulary.words
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
                    // The engine hears "flykit" as two words and the cleanup model will not
                    // rejoin it, so do it here where the answer is the user's own spelling.
                    text = VocabularySpelling.apply(words, to: text)
                }
                // Trailing space: dictation usually ends in punctuation, and the next words continue after a space.
                let inserted = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let result = await inserter.insert(inserted + " ")
                // Only what actually reached the field: `copiedOnly` means secure input refused
                // it, and that text must not reach the log or be diffed against someone's screen.
                if case .copiedOnly = result {
                    lastInsertion = nil
                } else {
                    lastInsertion = (inserted, context?.bundleID)
                    // The system log is capped and rotated by macOS, so this cannot grow unbounded.
                    if settings.debugLogging {
                        log.info("raw: \(raw, privacy: .public)\ncleaned: \(text, privacy: .public)")
                    }
                }
                state = .inserted(result: result)
                scheduleIdle(after: { if case .copiedOnly = result { return .seconds(2) } else { return .milliseconds(400) } }())
            } catch is CancellationError {
                state = .idle
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    /// Adds words the user fixed by hand after the last dictation to the vocabulary, so the
    /// speech engine and the cleaner both spell them right next time.
    ///
    /// The comparison rides on the context read that already happens here: whatever was
    /// inserted last time sits in `surroundingText` now, edits and all. No polling, no timer.
    /// It only fires in the same app, because elsewhere the text before the caret is someone
    /// else's. `surroundingText` is capped, so a long insertion is compared on its tail.
    private func learnCorrections(from context: AppContext?) async {
        // Each guard here is a silent no-op, and between them they explain every "it did not
        // learn anything" report, so say which one stopped it.
        guard let (inserted, bundleID) = lastInsertion else {
            log.info("learn: nothing inserted last time"); return
        }
        guard let context else { log.info("learn: no window context"); return }
        guard context.bundleID == bundleID else {
            log.info("learn: different app now (\(context.bundleID ?? "nil", privacy: .public) was \(bundleID ?? "nil", privacy: .public))"); return
        }
        // A terminal hides its text from Accessibility, but can hand over the whole visible
        // screen. Only worth the synthetic keystroke here, where it buys a learned word.
        var screen = context.surroundingText
        if screen == nil, TerminalScreenReader.supports(context.bundleID) {
            screen = await TerminalScreenReader.screenText(bundleID: context.bundleID)
        }
        guard let onScreen = screen else {
            log.info("learn: \(context.appName ?? context.bundleID ?? "this app", privacy: .public) does not expose its text to Accessibility"); return
        }
        lastInsertion = nil
        // Past the cap the tail begins mid-word, and that half-word reads as a correction of the
        // whole one ("tomorrow" -> "rrow"). Nothing here is salvageable, so learn nothing.
        guard inserted.utf16.count < WindowContextReader.textLimit else { return }
        let learned = CorrectionLearner.extractCorrections(
            originalText: inserted, fieldValue: onScreen, existingDictionary: vocabulary.words)
        guard !learned.isEmpty else {
            log.info("learn: no corrections found in the edits"); return
        }
        for word in learned { vocabulary.add(word) }
        log.info("learned \(learned.count) correction(s) from edits")
        do { try vocabulary.save() } catch { log.error("vocabulary save: \(error.localizedDescription, privacy: .public)") }
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
