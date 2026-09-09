import AppKit
import SwiftUI
import os
import UisperCore

/// `LSUIElement` keeps uisper out of the Dock, which also means it is never the active app:
/// `openSettings()` on its own puts the window behind whatever the user was looking at, and
/// they have to hunt for it. Activating first does not help, because the window does not exist
/// until the action has run, so it is raised on the next tick instead.
/// The overlay pill is skipped by `canBecomeKey`, which `OverlayPanel` overrides to false.
@MainActor
func showSettings(_ open: OpenSettingsAction) {
    let log = Logger(subsystem: "cc.flykit.uisper", category: "settings")
    open()
    NSApp.activate()
    Task { @MainActor in
        // Titled: the Settings window has a title bar, the MenuBarExtra's own window does not.
        let titled = NSApp.windows.filter { $0.canBecomeKey && $0.styleMask.contains(.titled) }
        log.info("settings: \(NSApp.windows.count, privacy: .public) windows, \(titled.count, privacy: .public) titled, active=\(NSApp.isActive, privacy: .public)")
        guard let window = titled.first else { return }
        window.makeKeyAndOrderFront(nil)
        // The one call that raises a window even while the app is not frontmost, which is the
        // normal state for an LSUIElement app.
        window.orderFrontRegardless()
    }
}

struct MenuBarView: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text("uisper · \(shortLanguage(model.settings.languageID)) · \(model.settings.hotkey.displayString)")
        if let err = model.hotkeyError { Text(err).foregroundStyle(.red) }
        Divider()
        Button("Settings…") { showSettings(openSettings) }.keyboardShortcut(",")
        Divider()
        Picker("Language", selection: Bindable(model.settings).languageID) {
            ForEach(model.settings.languages, id: \.self) { Text(displayName($0)).tag($0) }
        }
        Toggle("Clean up with AI", isOn: Bindable(model.settings).cleanupEnabled)
            .onChange(of: model.settings.cleanupEnabled) { model.ensureModel() }
        Picker("Mode", selection: Bindable(model.settings).mode) {
            Text("Hold to talk").tag(ActivationMode.hold)
            Text("Press to toggle").tag(ActivationMode.toggle)
        }
        Divider()
        Button("Quit uisper") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }

    private func shortLanguage(_ id: String) -> String { String(id.prefix(2)).uppercased() }
    private func displayName(_ id: String) -> String {
        Locale.current.localizedString(forIdentifier: id) ?? id
    }
}

/// The status-item label. It exists from launch, so its `.task` is where onboarding opens
/// Settings, using the documented `openSettings` action rather than a private selector.
struct MenuBarLabel: View {
    let model: AppModel
    let systemImage: String
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Label("uisper", systemImage: systemImage)
            .task {
                guard model.needsOnboarding else { return }
                model.needsOnboarding = false
                try? await Task.sleep(for: .seconds(1))   // let the permission prompts land first
                showSettings(openSettings)
            }
    }
}
