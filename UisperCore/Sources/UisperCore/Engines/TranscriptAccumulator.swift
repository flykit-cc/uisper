import Foundation

/// Merges volatile and final transcript segments into one running string.
public struct TranscriptAccumulator: Sendable, Equatable {
    public private(set) var finalized = ""
    public private(set) var volatile = ""

    public init() {}

    public var full: String { join(finalized, volatile) }

    /// Returns the full text after applying the update.
    @discardableResult
    public mutating func apply(text: String, isFinal: Bool) -> String {
        if isFinal {
            finalized = join(finalized, text)
            volatile = ""
        } else {
            volatile = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return full
    }

    private func join(_ a: String, _ b: String) -> String {
        let a = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = b.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + " " + b
    }
}
