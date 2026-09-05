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
        mode: ActivationMode = .hold
    ) -> (DictationSession, FakeSpeechEngine, FakeCleaner, FakeInserter, FakeAudio, SettingsStore) {
        let d = UserDefaults(suiteName: "uisper-session-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: d)
        settings.cleanupEnabled = cleanup
        settings.mode = mode
        settings.languageID = "de-DE"
        let vocab = VocabularyStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json"))
        vocab.add("Zephyr")
        let engine = FakeSpeechEngine(script: script)
        let cleaner = FakeCleaner()
        let inserter = FakeInserter()
        let audio = FakeAudio()
        let session = DictationSession(engine: engine, cleaner: cleaner, inserter: inserter, audio: audio, settings: settings, vocabulary: vocab)
        return (session, engine, cleaner, inserter, audio, settings)
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
        let (s, engine, cleaner, inserter, audio, _) = makeSession()
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

    @Test func cleanupOffInsertsRaw() async {
        let (s, _, cleaner, inserter, _, _) = makeSession(cleanup: false)
        s.handle(.pressed)
        try? await Task.sleep(for: .milliseconds(350))
        s.handle(.released)
        #expect(await waitUntil { !inserter.inserted.isEmpty })
        #expect(cleaner.calls.isEmpty)
        #expect(inserter.inserted == ["hello world "])
    }

    @Test func quickTapIsCancelled() async {
        let (s, _, _, inserter, audio, _) = makeSession()
        s.handle(.pressed)
        s.handle(.released)                       // < 300 ms
        #expect(await waitUntil { s.state == .idle })
        #expect(audio.stopped == 1)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(audio.started == 0)               // cancelled before the mic ever opened
        #expect(inserter.inserted.isEmpty)
    }

    @Test func cancelDropsTranscript() async {
        let (s, _, _, inserter, _, _) = makeSession()
        s.handle(.pressed)
        try? await Task.sleep(for: .milliseconds(350))
        s.handle(.cancelled)
        #expect(await waitUntil { s.state == .idle })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(inserter.inserted.isEmpty)
    }

    @Test func emptyTranscriptShowsNothingHeard() async {
        let (s, _, _, inserter, _, _) = makeSession(script: [])
        s.handle(.pressed)
        try? await Task.sleep(for: .milliseconds(350))
        s.handle(.released)
        #expect(await waitUntil { s.state == .error("Nothing heard.") })
        #expect(inserter.inserted.isEmpty)
    }

    @Test func cleanerFailureFallsBackToRaw() async {
        let (s, _, cleaner, inserter, _, _) = makeSession()
        cleaner.error = NSError(domain: "x", code: 1)
        s.handle(.pressed)
        try? await Task.sleep(for: .milliseconds(350))
        s.handle(.released)
        #expect(await waitUntil { !inserter.inserted.isEmpty })
        #expect(inserter.inserted == ["hello world "])
    }

    @Test func toggleModeStartsAndStopsOnPress() async {
        let (s, _, _, inserter, audio, _) = makeSession(mode: .toggle)
        s.handle(.pressed); s.handle(.released)    // first press+release starts, release ignored
        #expect(await waitUntil { if case .listening = s.state { return true }; return false })
        try? await Task.sleep(for: .milliseconds(350))
        #expect(audio.stopped == 0)
        s.handle(.pressed)                          // second press stops
        #expect(await waitUntil { !inserter.inserted.isEmpty })
    }
}
