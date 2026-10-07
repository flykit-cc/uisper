import AVFoundation
import Foundation
import Testing
@testable import UisperCore

@MainActor
final class FakeAudio: AudioSource {
    var level: Float = 0
    var started = 0
    var stopped = 0
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    func start(targetFormat: AVAudioFormat?) throws -> sending AsyncStream<AVAudioPCMBuffer> {
        started += 1
        let (s, c) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        continuation = c
        return s
    }
    func stop() { stopped += 1; continuation?.finish(); continuation = nil }
}

@MainActor
struct DictationSessionTests {
    private func makeSession(
        script: [TranscriptUpdate] = [TranscriptUpdate(text: "hello wor", isFinal: false), TranscriptUpdate(text: "hello world", isFinal: true)],
        cleanup: Bool = true,
        mode: ActivationMode = .hold,
        language: String = "de-DE",
        contextProvider: @escaping @MainActor () -> AppContext? = { nil },
        now: @escaping @MainActor () -> ContinuousClock.Instant = { .now }
    ) -> (DictationSession, FakeSpeechEngine, FakeCleaner, FakeInserter, FakeAudio, SettingsStore, VocabularyStore) {
        let d = UserDefaults(suiteName: "uisper-session-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: d)
        settings.cleanupEnabled = cleanup
        settings.mode = mode
        settings.languageID = language
        let vocab = VocabularyStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json"))
        vocab.add("Zephyr")
        let engine = FakeSpeechEngine(script: script)
        let cleaner = FakeCleaner()
        let inserter = FakeInserter()
        let audio = FakeAudio()
        let session = DictationSession(engines: [.apple: engine], cleaner: cleaner, inserter: inserter, audio: audio, settings: settings, vocabulary: vocab, contextProvider: contextProvider, now: now)
        return (session, engine, cleaner, inserter, audio, settings, vocab)
    }

    private func waitUntil(_ cond: @escaping @MainActor () -> Bool, timeout: Duration = .seconds(3)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if cond() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return cond()
    }

    @Test func fullFlowCleansAndInserts() async {
        let (s, engine, cleaner, inserter, audio, _, _) = makeSession()
        s.handle(.pressed)
        // `.listening` is set synchronously by `handle`; the mic opens on the engine task.
        #expect({ if case .listening = s.state { return true }; return false }())
        #expect(await waitUntil { audio.started == 1 })
        try? await Task.sleep(for: .milliseconds(350))
        s.handle(.released)
        #expect(await waitUntil { if case .inserted = s.state { return true }; return false })
        #expect(audio.stopped == 1)
        #expect(engine.startedLocales.first?.identifier == "de-DE")
        #expect(cleaner.calls.first?.raw == "hello world")
        #expect(cleaner.calls.first?.vocabulary == ["Zephyr"])
        #expect(inserter.inserted == ["CLEAN(hello world) "])
        #expect(await waitUntil { s.state == .idle })
    }

    @Test func cleanupOffInsertsRawAndReadsNoScreenText() async {
        var contextReads = 0
        let (s, _, cleaner, inserter, _, _, _) = makeSession(cleanup: false, contextProvider: { contextReads += 1; return nil })
        s.handle(.pressed)
        try? await Task.sleep(for: .milliseconds(350))
        s.handle(.released)
        #expect(await waitUntil { !inserter.inserted.isEmpty })
        #expect(cleaner.calls.isEmpty)
        #expect(inserter.inserted == ["hello world "])
        #expect(contextReads == 0)
    }

    @Test func quickTapIsCancelled() async {
        let (s, _, _, inserter, audio, _, _) = makeSession()
        s.handle(.pressed)
        s.handle(.released)                       // < 300 ms
        #expect(await waitUntil { s.state == .idle })
        #expect(audio.stopped == 1)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(audio.started == 0)               // cancelled before the mic ever opened
        #expect(inserter.inserted.isEmpty)
    }

    @Test func cancelDropsTranscript() async {
        let (s, _, _, inserter, _, _, _) = makeSession()
        s.handle(.pressed)
        try? await Task.sleep(for: .milliseconds(350))
        s.handle(.cancelled)
        #expect(await waitUntil { s.state == .idle })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(inserter.inserted.isEmpty)
    }

    @Test func emptyTranscriptShowsNothingHeard() async {
        let (s, _, _, inserter, _, _, _) = makeSession(script: [])
        s.handle(.pressed)
        try? await Task.sleep(for: .milliseconds(350))
        s.handle(.released)
        #expect(await waitUntil { s.state == .error("Nothing heard.") })
        #expect(inserter.inserted.isEmpty)
    }

    @Test func cleanerFailureFallsBackToRaw() async {
        let (s, _, cleaner, inserter, _, _, _) = makeSession()
        cleaner.error = NSError(domain: "x", code: 1)
        s.handle(.pressed)
        try? await Task.sleep(for: .milliseconds(350))
        s.handle(.released)
        #expect(await waitUntil { !inserter.inserted.isEmpty })
        #expect(inserter.inserted == ["hello world "])
    }

    @Test func toggleModeStartsAndStopsOnPress() async {
        let (s, _, _, inserter, audio, _, _) = makeSession(mode: .toggle)
        s.handle(.pressed); s.handle(.released)    // first press+release starts, release ignored
        #expect(await waitUntil { if case .listening = s.state { return true }; return false })
        try? await Task.sleep(for: .milliseconds(350))
        #expect(audio.stopped == 0)
        s.handle(.pressed)                          // second press stops
        #expect(await waitUntil { !inserter.inserted.isEmpty })
    }

    /// Ten minutes, not cancelled: a walked-away toggle must not hold audio for ever, and the
    /// words already spoken are still the user's.
    @Test func aDictationHasAnUpperBound() {
        #expect(DictationSession.maxDictation == .seconds(600))
    }

    @Test func englishFillersAreRemovedEvenWithCleanupOff() async {
        let (s, _, _, inserter, _, _, _) = makeSession(
            script: [TranscriptUpdate(text: "um, hello world", isFinal: true)], cleanup: false, language: "en-US")
        s.handle(.pressed)
        try? await Task.sleep(for: .milliseconds(350))
        s.handle(.released)
        #expect(await waitUntil { inserter.inserted.count == 1 })
        #expect(inserter.inserted == ["hello world "])
    }

    /// Dictates the same misheard sentence twice, with the user's fix on screen in between and
    /// the clock moved on by `gap`, and returns the vocabulary afterwards.
    private func learnAfter(_ gap: Duration) async -> VocabularyStore {
        var clock = ContinuousClock.now
        var screen = ""
        let (s, _, cleaner, inserter, _, _, vocab) = makeSession(
            script: [TranscriptUpdate(text: "I spoke to Shunade about it", isFinal: true)],
            contextProvider: { AppContext(bundleID: "com.test", appName: "Test", windowTitle: nil, surroundingText: screen) },
            now: { clock })
        cleaner.transform = { $0 }
        for round in 1...2 {
            s.handle(.pressed)
            try? await Task.sleep(for: .milliseconds(350))
            s.handle(.released)
            #expect(await waitUntil { inserter.inserted.count == round })
            #expect(await waitUntil { s.state == .idle })
            screen = "I spoke to Sinead about it"
            clock += gap
        }
        return vocab
    }

    @Test func editsAreLearnedWithinTheWindowAndTaggedLearned() async {
        let vocab = await learnAfter(.seconds(60))
        #expect(vocab.words.contains("Sinead"))
        #expect(vocab.source(of: "Sinead") == .learned)
    }

    @Test func editsAfterTheWindowAreNotLearned() async {
        let vocab = await learnAfter(.seconds(360))
        #expect(!vocab.words.contains("Sinead"))
    }
}
