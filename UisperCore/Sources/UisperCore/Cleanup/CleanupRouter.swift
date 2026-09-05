import Foundation

/// Sends each cleanup to the engine chosen in Settings. Both engines stay alive so switching is instant.
@MainActor
public final class CleanupRouter: TranscriptCleaner {
    private let settings: SettingsStore
    private let engines: [CleanupEngine: TranscriptCleaner]

    public init(settings: SettingsStore, engines: [CleanupEngine: TranscriptCleaner]) {
        self.settings = settings
        self.engines = engines
    }

    public func clean(_ raw: String, locale: Locale, vocabulary: [String], context: AppContext?) async throws -> String {
        let engine = engines[settings.cleanupEngine] ?? PassthroughCleaner()
        return try await engine.clean(raw, locale: locale, vocabulary: vocabulary, context: context)
    }
}
