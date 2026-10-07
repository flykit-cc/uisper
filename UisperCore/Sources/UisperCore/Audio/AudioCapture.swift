import AVFoundation
import Observation
import os

/// Captures the default input device and streams buffers, converted to `targetFormat`.
@MainActor
@Observable
public final class AudioCapture {
    public private(set) var level: Float = 0

    private var engine = AVAudioEngine()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private let log = Logger(subsystem: "cc.flykit.uisper", category: "audio")

    public init() {}

    /// `sending`: the buffers are not Sendable, so the caller takes sole ownership of the stream.
    public func start(targetFormat: AVAudioFormat?) throws -> sending AsyncStream<AVAudioPCMBuffer> {
        stop()
        // A fresh engine each time: a reused one keeps the mic format from before a device change
        // (headphones in or out), and installTap then throws an Objective-C exception. Swift cannot
        // catch it; AppKit swallows it, which corrupts the main actor's state and segfaults the app
        // at the next isolation check.
        engine = AVAudioEngine()
        let input = engine.inputNode
        let micFormat = input.outputFormat(forBus: 0)
        guard micFormat.sampleRate > 0, micFormat.channelCount > 0 else {
            throw SpeechEngineError.engineFailed("No microphone input available")
        }
        let converter = try targetFormat.map { try BufferConverter(from: micFormat, to: $0) }
        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream(bufferingPolicy: .unbounded)
        self.continuation = continuation

        // @Sendable severs the inherited @MainActor isolation: the tap really runs on an
        // audio thread, so the level update below has to hop back to the main actor.
        input.installTap(onBus: 0, bufferSize: 2048, format: micFormat) { @Sendable [weak self, converter, continuation] buffer, _ in
            let rms = AudioLevel.rms(buffer)
            // AVAudioPCMBuffer is not Sendable and the tap's buffer is not a `sending`
            // parameter, so the compiler cannot prove the handoff is safe. It is: nothing
            // here touches the buffer after the yield.
            nonisolated(unsafe) let out: AVAudioPCMBuffer
            if let converter {
                guard let converted = try? converter.convert(buffer) else { return }
                out = converted
            } else {
                out = buffer
            }
            continuation.yield(out)
            Task { @MainActor in self?.level = rms }
        }
        engine.prepare()
        try engine.start()
        log.info("capture started \(micFormat.sampleRate, privacy: .public) Hz → \(targetFormat?.sampleRate ?? micFormat.sampleRate, privacy: .public) Hz")
        return stream
    }

    public func stop() {
        guard continuation != nil else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
        level = 0
        log.info("capture stopped")
    }
}
