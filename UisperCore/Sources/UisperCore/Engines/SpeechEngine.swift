import AVFoundation
import Foundation

/// One update from a speech engine. `text` is this segment's current hypothesis.
/// Volatile updates replace the previous volatile text; final updates are appended for good.
public struct TranscriptUpdate: Sendable, Equatable {
    public let text: String
    public let isFinal: Bool
    public init(text: String, isFinal: Bool) { self.text = text; self.isFinal = isFinal }
}

public protocol SpeechEngine: Sendable {
    var id: EngineID { get }
    func supports(_ locale: Locale) async -> Bool
    /// Downloads/installs anything the locale needs. Safe to call every time.
    func prepare(locale: Locale) async throws
    /// The audio format the engine wants. `AudioCapture` converts into it. `nil` = use the mic format.
    func preferredFormat() async -> AVAudioFormat?
    /// Streams updates until `audio` finishes, then finalizes and ends the stream.
    /// `audio` is `sending`: `AVAudioPCMBuffer` is not `Sendable`, so the caller hands the
    /// stream over and must not read it afterwards. Without this an engine cannot drain the
    /// stream from a `Task` under Swift 6 strict concurrency.
    func start(locale: Locale, audio: sending AsyncStream<AVAudioPCMBuffer>) -> AsyncThrowingStream<TranscriptUpdate, Error>
}

public enum SpeechEngineError: Error, LocalizedError, Sendable {
    case unsupportedLocale(String)
    case assetsMissing(String)
    case engineFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let l): return "Language \(l) is not supported by this engine."
        case .assetsMissing(let l): return "Speech model for \(l) is not installed yet."
        case .engineFailed(let m): return m
        }
    }
}
