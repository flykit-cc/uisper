// TEMPORARY: mirrors the enum Task 3 defines in Sources/UisperCore/Engines/SpeechEngine.swift.
// Delete this file at merge time, once Task 3 lands.
import Foundation

public enum SpeechEngineError: Error, LocalizedError, Sendable {
    case unsupportedLocale(String)
    case assetsMissing(String)
    case engineFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let s): "Unsupported locale: \(s)"
        case .assetsMissing(let s): "Assets missing: \(s)"
        case .engineFailed(let s): s
        }
    }
}
