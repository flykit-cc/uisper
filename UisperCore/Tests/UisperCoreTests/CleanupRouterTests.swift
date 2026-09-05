import Foundation
import Testing
@testable import UisperCore

@MainActor
struct CleanupRouterTests {
    @Test func routesToTheEngineChosenInSettings() async throws {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "uisper-router-\(UUID().uuidString)")!)
        let builtIn = FakeCleaner(); builtIn.transform = { "B(" + $0 + ")" }
        let apple = FakeCleaner(); apple.transform = { "A(" + $0 + ")" }
        let router = CleanupRouter(settings: settings, engines: [.builtIn: builtIn, .apple: apple])
        let locale = Locale(identifier: "en-US")
        settings.cleanupEngine = .apple
        #expect(try await router.clean("x", locale: locale, vocabulary: [], context: nil) == "A(x)")
        settings.cleanupEngine = .builtIn
        #expect(try await router.clean("x", locale: locale, vocabulary: [], context: nil) == "B(x)")
    }

    @Test func missingEnginePassesThrough() async throws {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "uisper-router-\(UUID().uuidString)")!)
        let router = CleanupRouter(settings: settings, engines: [:])
        #expect(try await router.clean("raw", locale: Locale(identifier: "en-US"), vocabulary: [], context: nil) == "raw")
    }
}
