import AVFoundation
import Testing
@testable import UisperCore

struct BufferConverterTests {
    private func sine(format: AVAudioFormat, frames: AVAudioFrameCount, amplitude: Float) -> AVAudioPCMBuffer {
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        let ch = buf.floatChannelData![0]
        for i in 0..<Int(frames) { ch[i] = amplitude * sin(Float(i) * 0.05) }
        return buf
    }

    @Test func resamples48kTo16kMono() throws {
        let from = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let to = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
        let conv = try BufferConverter(from: from, to: to)
        // AVAudioConverter's resampler primes a filter delay, so its first call emits ~240
        // frames fewer than the ideal. Prime it, then assert on the steady state that
        // streaming capture actually sees: 4800 frames at 48 kHz become ~1600 at 16 kHz.
        _ = try conv.convert(sine(format: from, frames: 4800, amplitude: 0.5))
        let out = try conv.convert(sine(format: from, frames: 4800, amplitude: 0.5))
        #expect(out.format.sampleRate == 16_000)
        #expect(abs(Int(out.frameLength) - 1600) <= 16)
    }

    @Test func rmsIsZeroForSilenceAndPositiveForSignal() {
        let f = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        #expect(AudioLevel.rms(sine(format: f, frames: 1600, amplitude: 0)) == 0)
        let loud = AudioLevel.rms(sine(format: f, frames: 1600, amplitude: 0.8))
        #expect(loud > 0.3 && loud <= 1)
    }
}
