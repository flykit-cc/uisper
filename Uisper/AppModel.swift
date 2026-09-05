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
    private(set) var cleanupNotice: String?

    private let inserter: TextInserter
    private let overlay: OverlayController
    private var hotkey: HotkeyMonitor?
    private let log = Logger(subsystem: "cc.flykit.uisper", category: "app")

    init() {
        let settings = SettingsStore()
        let vocabulary = VocabularyStore(fileURL: VocabularyStore.defaultURL())
        let inserter = TextInserter()
        let engine = AppleSpeechEngine(contextualStrings: { MainActor.assumeIsolated { vocabulary.words } })
        let cleaner: TranscriptCleaner
        var notice: String?
        if let msg = FoundationModelsCleaner.availabilityMessage {
            cleaner = PassthroughCleaner()
            notice = msg + " Text will be inserted without cleanup."
        } else {
            cleaner = FoundationModelsCleaner()
        }
        let session = DictationSession(
            engine: engine, cleaner: cleaner, inserter: inserter, audio: AudioCapture(),
            settings: settings, vocabulary: vocabulary,
            contextProvider: { inserter.focusedContext() }
        )
        self.settings = settings
        self.vocabulary = vocabulary
        self.inserter = inserter
        self.session = session
        self.cleanupNotice = notice
        self.overlay = OverlayController(session: session, anchor: { inserter.focusedWindowFrame() })
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
