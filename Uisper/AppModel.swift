import AppKit
import CoreGraphics
import Observation
import ServiceManagement
import UisperCore
import os

/// Owns every long-lived object and wires them together.
@MainActor
@Observable
final class AppModel {
    let settings: SettingsStore
    let vocabulary: VocabularyStore
    let session: DictationSession
    private(set) var hotkeyError: String?
    let modelDownload: ModelDownload
    /// Why the Apple engine cannot run, or nil when it can.
    private let appleNotice: String?
    private var mlx: MLXCleaner?

    /// One line for the Settings pane about the chosen engine, or nil when it is ready.
    var cleanupNotice: String? {
        switch settings.cleanupEngine {
        case .apple: return appleNotice
        case .builtIn:
            switch modelDownload.state {
            case .ready: return nil
            case .missing: return "The built-in model (\(ModelDownload.sizeLabel)) is not downloaded yet."
            case .downloading(let f): return "Downloading the built-in model (\(ModelDownload.sizeLabel))… \(Int(f * 100))%. Text is inserted without cleanup until it is done."
            case .failed(let e): return "Model download failed: \(e)"
            }
        }
    }

    private let inserter: TextInserter
    private let overlay: OverlayController
    private var hotkey: HotkeyMonitor?
    private let log = Logger(subsystem: "cc.flykit.uisper", category: "app")

    init() {
        let settings = SettingsStore()
        let vocabulary = VocabularyStore(fileURL: VocabularyStore.defaultURL())
        let inserter = TextInserter()
        let engine = AppleSpeechEngine(contextualStrings: { MainActor.assumeIsolated { vocabulary.words } })
        let modelDownload = ModelDownload()
        var engines: [CleanupEngine: TranscriptCleaner] = [:]
        let mlx = MLXCleaner(directory: modelDownload.directory)
        engines[.builtIn] = mlx
        var appleNotice: String?
        if let msg = FoundationModelsCleaner.availabilityMessage {
            appleNotice = msg + " Text will be inserted without cleanup."
        } else {
            engines[.apple] = FoundationModelsCleaner()
        }
        let cleaner = CleanupRouter(settings: settings, engines: engines)
        let session = DictationSession(
            engine: engine, cleaner: cleaner, inserter: inserter, audio: AudioCapture(),
            settings: settings, vocabulary: vocabulary,
            contextProvider: { WindowContextReader().read() }
        )
        self.settings = settings
        self.vocabulary = vocabulary
        self.inserter = inserter
        self.session = session
        self.appleNotice = appleNotice
        self.modelDownload = modelDownload
        self.mlx = mlx
        self.overlay = OverlayController(session: session, anchor: { inserter.focusedWindowFrame() })
        ensureModel()
        startHotkey()
        let granted = Permissions.allGranted
        log.info("launch: permissions granted=\(granted, privacy: .public)")
        guard !granted else { return }
        needsOnboarding = true
        Task { @MainActor in
            _ = await Permissions.request(.microphone)
            _ = await Permissions.request(.accessibility)
            _ = await Permissions.request(.inputMonitoring)
            // The event tap can only be created once Input Monitoring is granted.
            self.startHotkey()
            NSApp.activate()
        }
    }

    /// True at launch when a permission is missing. `MenuBarLabel` opens Settings for it.
    var needsOnboarding = false

    func startHotkey() {
        hotkey?.stop()
        let session = self.session
        let monitor = HotkeyMonitor(hotkey: settings.hotkey) { event in session.handle(event) }
        monitor.isDictating = { if case .listening = session.state { return true } else { return false } }
        do {
            try monitor.start()
            hotkey = monitor
            hotkeyError = nil
        } catch {
            hotkey = nil
            hotkeyError = error.localizedDescription
            log.error("hotkey: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Downloads and warms the built-in model when it is the chosen engine. Cheap to call often.
    func ensureModel() {
        guard settings.cleanupEnabled, settings.cleanupEngine == .builtIn, let mlx else { return }
        Task {
            do { try await modelDownload.ensure() } catch { return }
            await mlx.prewarm()
        }
    }

    func hotkeyChanged() {
        hotkey?.hotkey = settings.hotkey
    }

    /// While the recorder field is capturing, the tap routes keys to it instead of dictation.
    func setHotkeyRecording(_ sink: (@MainActor (CGEventType, Int64, CGEventFlags) -> Bool)?) {
        hotkey?.recordingSink = sink
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            settings.launchAtLogin = on
        } catch {
            log.error("launch at login: \(error.localizedDescription, privacy: .public)")
        }
    }

    func saveVocabulary() {
        do { try vocabulary.save() } catch { log.error("vocabulary save: \(error.localizedDescription, privacy: .public)") }
    }
}
