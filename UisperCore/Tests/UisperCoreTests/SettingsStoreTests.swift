import Foundation
import Testing
@testable import UisperCore

@MainActor
struct SettingsStoreTests {
    private func freshDefaults() -> UserDefaults {
        let name = "uisper-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func defaultsAreSane() {
        let s = SettingsStore(defaults: freshDefaults())
        #expect(s.languageID == "en-US")
        #expect(s.mode == .hold)
        #expect(s.hotkey == .optionSpace)
        #expect(s.engine == .apple)
        #expect(s.cleanupEnabled == true)
        #expect(s.launchAtLogin == false)
        #expect(s.locale.identifier == "en-US")
    }

    @Test func valuesPersistAcrossInstances() {
        let d = freshDefaults()
        let a = SettingsStore(defaults: d)
        a.languageID = "de-DE"
        a.mode = .toggle
        a.cleanupEnabled = false
        let b = SettingsStore(defaults: d)
        #expect(b.languageID == "de-DE")
        #expect(b.mode == .toggle)
        #expect(b.cleanupEnabled == false)
    }

    @Test func cycleLanguageWraps() {
        let s = SettingsStore(defaults: freshDefaults())
        s.cycleLanguage(); #expect(s.languageID == "de-DE")
        s.cycleLanguage(); #expect(s.languageID == "pt-BR")
        s.cycleLanguage(); #expect(s.languageID == "en-US")
    }

    @Test func hotkeyPersistsAndMigrates() {
        let d = freshDefaults()
        let a = SettingsStore(defaults: d)
        a.hotkey = Hotkey(keyCode: 105, modifiers: 0)
        #expect(SettingsStore(defaults: d).hotkey == Hotkey(keyCode: 105, modifiers: 0))

        let legacy = freshDefaults()
        legacy.set("fn", forKey: "hotkey")
        #expect(SettingsStore(defaults: legacy).hotkey == .fn)
    }
}
