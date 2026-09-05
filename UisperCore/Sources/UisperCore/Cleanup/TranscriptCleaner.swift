import Foundation

/// What the user is typing into.
public struct AppContext: Sendable, Equatable {
    public let bundleID: String?
    public let appName: String?
    public let windowTitle: String?
    /// Text just before the caret in the focused field, for tone and names. nil when the app hides it.
    public let surroundingText: String?
    public init(bundleID: String?, appName: String?, windowTitle: String?, surroundingText: String? = nil) {
        self.bundleID = bundleID; self.appName = appName; self.windowTitle = windowTitle
        self.surroundingText = surroundingText
    }
}

public protocol TranscriptCleaner: Sendable {
    func clean(_ raw: String, locale: Locale, vocabulary: [String], context: AppContext?) async throws -> String
}

/// Used when cleanup is off or the local model is unavailable.
public struct PassthroughCleaner: TranscriptCleaner {
    public init() {}
    public func clean(_ raw: String, locale: Locale, vocabulary: [String], context: AppContext?) async throws -> String { raw }
}
