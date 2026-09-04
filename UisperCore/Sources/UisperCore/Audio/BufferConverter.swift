import AVFoundation

/// Converts mic buffers into the format a speech engine asks for.
/// SpeechAnalyzer silently transcribes nothing on a format mismatch, so this is not optional.
public struct BufferConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let to: AVAudioFormat

    public init(from: AVAudioFormat, to: AVAudioFormat) throws {
        guard let c = AVAudioConverter(from: from, to: to) else {
            throw SpeechEngineError.engineFailed("Cannot convert \(from) to \(to)")
        }
        converter = c
        self.to = to
    }

    public func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let ratio = to.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: to, frameCapacity: capacity) else {
            throw SpeechEngineError.engineFailed("Cannot allocate output buffer")
        }
        var error: NSError?
        nonisolated(unsafe) var consumed = false
        // The input block runs synchronously on this thread, so handing it the caller's
        // buffer is safe; the compiler cannot see that, hence nonisolated(unsafe).
        nonisolated(unsafe) let input = buffer
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if consumed { outStatus.pointee = .noDataNow; return nil }
            consumed = true
            outStatus.pointee = .haveData
            return input
        }
        if let error { throw error }
        if status == .error { throw SpeechEngineError.engineFailed("Audio conversion failed") }
        return out
    }
}

public enum AudioLevel {
    /// Root-mean-square of the first channel, clamped to 0...1. Works for float buffers; 0 otherwise.
    public static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += data[0][i] * data[0][i] }
        return min(1, (sum / Float(n)).squareRoot())
    }
}
