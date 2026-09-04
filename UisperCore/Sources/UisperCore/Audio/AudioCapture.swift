import AVFoundation
import Observation
import os

/// Captures the default input device and streams buffers, converted to `targetFormat`.
@MainActor
@Observable
public final class AudioCapture {
    public private(set) var level: Float = 0

    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private let log = Logger(subsystem: "cc.flykit.uisper", category: "audio")

    public init() {}

    public func start(targetFormat: AVAudioFormat?) throws -> AsyncStream<AVAudioPCMBuffer> {
        stop()
        let input = engine.inputNode
        let micFormat = input.outputFormat(forBus: 0)
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
