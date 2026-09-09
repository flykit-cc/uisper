import AVFoundation
import FluidAudio
import Foundation
import UisperCore
import os

/// Parakeet TDT v3 (0.6B) running on the Apple Neural Engine, through FluidAudio.
///
/// Batch, not streaming: nothing is transcribed until the user lets go. On a push-to-talk
/// dictation that costs a fraction of a second on Apple Silicon, and it buys one model for
/// 25 European languages with the language as an optional hint rather than a hard setting.
/// The trade against `AppleSpeechEngine` is the live preview: there is no volatile text to
/// show while the user is still speaking.
public final class ParakeetEngine: SpeechEngine {
    /// The rate the CoreML models are exported for. `AudioCapture` converts into it.
    static let sampleRate = 16_000.0

    public let id: EngineID = .parakeet
    private let store: ModelStore
    private let log = Logger(subsystem: "cc.flykit.uisper", category: "parakeet")

    init(download: SpeechModelDownload) {
        store = ModelStore(download: download)
    }

    /// True for the 25 European languages the v3 model covers.
    public func supports(_ locale: Locale) async -> Bool {
        Self.language(for: locale) != nil
    }

    /// Downloads (~600 MB, once) and loads the model. Safe to call every time.
    public func prepare(locale: Locale) async throws {
        guard await supports(locale) else {
            throw SpeechEngineError.unsupportedLocale(locale.identifier)
        }
        do { _ = try await store.manager() } catch {
            throw SpeechEngineError.assetsMissing(error.localizedDescription)
        }
    }

    public func preferredFormat() async -> AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate,
                      channels: 1, interleaved: false)
    }

    public func start(locale: Locale, audio: sending AsyncStream<AVAudioPCMBuffer>) -> AsyncThrowingStream<TranscriptUpdate, Error> {
        let (stream, continuation) = AsyncThrowingStream<TranscriptUpdate, Error>.makeStream()
        let hint = Self.language(for: locale)

        // `audio` is `sending`, so exactly one task may consume it and that task has to be
        // spawned here, while the value is still disconnected. Same split as AppleSpeechEngine.
        let (samples, collected) = AsyncStream<[Float]>.makeStream()
        let feed = Task {
            for await buffer in audio { collected.yield(Self.floats(buffer)) }
            collected.finish()
        }

        let task = Task {
            do {
                // Load alongside the drain: waiting for a cold model first would let buffers
                // pile up unread, and on a warm one this costs nothing.
                async let pending = store.manager()
                var pcm: [Float] = []
                for await chunk in samples { pcm.append(contentsOf: chunk) }
                _ = await feed.result
                // Only one update is ever emitted, at the end, so nothing downstream notices a
                // cancel until then. Without this a cancelled dictation still runs the model.
                try Task.checkCancellation()

                guard !pcm.isEmpty else { continuation.finish(); return }
                let manager = try await pending
                let started = ContinuousClock.now
                var state = try TdtDecoderState()
                let result = try await manager.transcribe(pcm, decoderState: &state, language: hint)
                let seconds = Double(pcm.count) / Self.sampleRate
                log.info("transcribed \(seconds, privacy: .public) s of audio in \(ContinuousClock.now - started, privacy: .public)")

                // Deliberately nothing between the model and the cleaner. Acoustic word boosting
                // and inverse text normalisation were both tried here and both made the output
                // worse ("which is fine" became "which is Deepseek", "ten thirty" became "1030").
                // The word list and the number rules live in the cleanup prompt instead, where a
                // mistake is a wrong word rather than a destroyed sentence.
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { continuation.yield(TranscriptUpdate(text: text, isFinal: true)) }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish()
            } catch {
                log.error("engine failed: \(error.localizedDescription, privacy: .public)")
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

    /// The mono float samples of one buffer.
    private static func floats(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    /// FluidAudio takes a bare language code; `Locale` carries a region we drop.
    /// The hint only filters candidate tokens by script, so an unknown language is not fatal.
    static func language(for locale: Locale) -> Language? {
        locale.language.languageCode.map(\.identifier).flatMap(Language.init(rawValue:))
    }
}

/// Loads the model once and hands the same manager to every dictation.
private actor ModelStore {
    private var loaded: AsrManager?
    private var loading: Task<AsrManager, Error>?
    private let download: SpeechModelDownload
    private let log = Logger(subsystem: "cc.flykit.uisper", category: "parakeet")

    init(download: SpeechModelDownload) { self.download = download }

    func manager() async throws -> AsrManager {
        if let loaded { return loaded }
        if let loading { return try await loading.value }
        let download = self.download
        let task = Task {
            let started = ContinuousClock.now
            do {
                let models = try await AsrModels.downloadAndLoad(version: .v3) { progress in
                    // Called on whatever queue FluidAudio is using, so hop before touching UI.
                    Task { @MainActor in
                        switch progress.phase {
                        case .downloading(let done, let total):
                            download.report(.downloading(fraction: progress.fractionCompleted,
                                                         completedFiles: done, totalFiles: total))
                        case .compiling:
                            download.report(.compiling)
                        default:
                            download.report(.downloading(fraction: progress.fractionCompleted,
                                                         completedFiles: 0, totalFiles: 0))
                        }
                    }
                }
                log.info("model loaded in \(ContinuousClock.now - started, privacy: .public)")
                await MainActor.run { download.report(.ready) }
                return AsrManager(models: models)
            } catch {
                log.error("model load failed: \(error.localizedDescription, privacy: .public)")
                await MainActor.run { download.report(.failed(error.localizedDescription)) }
                throw error
            }
        }
        loading = task
        defer { loading = nil }
        let manager = try await task.value
        loaded = manager
        return manager
    }
}
