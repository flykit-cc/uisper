import Foundation

/// What the user is typing into. Stage 1 fills only what the inserter can see cheaply; Stage 3 adds more.
public struct AppContext: Sendable, Equatable {
    public let bundleID: String?
    public let appName: String?
    public let windowTitle: String?
    public init(bundleID: String?, appName: String?, windowTitle: String?) {
        self.bundleID = bundleID; self.appName = appName; self.windowTitle = windowTitle
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
