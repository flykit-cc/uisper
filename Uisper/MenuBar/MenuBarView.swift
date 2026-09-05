import SwiftUI
import UisperCore

struct MenuBarView: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text("uisper · \(shortLanguage(model.settings.languageID)) · \(model.settings.hotkey.displayString)")
        if let err = model.hotkeyError { Text(err).foregroundStyle(.red) }
        Divider()
        Button("Settings…") { openSettings() }.keyboardShortcut(",")
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
                openSettings()
            }
    }
}
