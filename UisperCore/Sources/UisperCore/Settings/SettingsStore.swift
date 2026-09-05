import Foundation
import Observation

public enum EngineID: String, Codable, CaseIterable, Sendable { case apple, whisper }
public enum ActivationMode: String, Codable, CaseIterable, Sendable { case hold, toggle }

/// User preferences, backed by UserDefaults. Observable so SwiftUI updates.
@MainActor
@Observable
public final class SettingsStore {
    public static let supportedLanguages = ["en-US", "de-DE", "pt-BR"]

    private let defaults: UserDefaults

    public var languageID: String { didSet { defaults.set(languageID, forKey: "languageID") } }
    public var mode: ActivationMode { didSet { defaults.set(mode.rawValue, forKey: "mode") } }
    public var hotkey: Hotkey { didSet { defaults.set(try? JSONEncoder().encode(hotkey), forKey: "hotkey") } }
    public var engine: EngineID { didSet { defaults.set(engine.rawValue, forKey: "engine") } }
    public var cleanupEnabled: Bool { didSet { defaults.set(cleanupEnabled, forKey: "cleanupEnabled") } }
    public var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") } }

    public var languages: [String] { Self.supportedLanguages }
    public var locale: Locale { Locale(identifier: languageID) }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        languageID = defaults.string(forKey: "languageID") ?? "en-US"
        mode = ActivationMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .hold
        if let data = defaults.data(forKey: "hotkey"), let stored = try? JSONDecoder().decode(Hotkey.self, from: data) {
            hotkey = stored
        } else {
            // Migrate the pre-1.0 two-option picker, which stored a raw string.
            hotkey = defaults.string(forKey: "hotkey") == "fn" ? .fn : .optionSpace
        }
        engine = EngineID(rawValue: defaults.string(forKey: "engine") ?? "") ?? .apple
        cleanupEnabled = defaults.object(forKey: "cleanupEnabled") as? Bool ?? true
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
    }

    public func cycleLanguage() {
        let list = Self.supportedLanguages
        let i = list.firstIndex(of: languageID) ?? 0
        languageID = list[(i + 1) % list.count]
    }
}
