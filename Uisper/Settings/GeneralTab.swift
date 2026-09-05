import SwiftUI
import UisperCore

struct GeneralTab: View {
    let model: AppModel

    var body: some View {
        Form {
            LabeledContent("Hotkey") {
                VStack(alignment: .leading, spacing: 4) {
                    HotkeyRecorderView(
                        hotkey: Bindable(model.settings).hotkey,
                        onRecordingChanged: model.setHotkeyRecording
                    )
                    Text("Click the field, then press your shortcut. Esc cancels, ⌫ resets to ⌥ Space.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .onChange(of: model.settings.hotkey) { _, _ in model.hotkeyChanged() }
            Picker("Mode", selection: Bindable(model.settings).mode) {
                Text("Hold to talk").tag(ActivationMode.hold)
                Text("Press to toggle").tag(ActivationMode.toggle)
            }
            Picker("Language", selection: Bindable(model.settings).languageID) {
                ForEach(model.settings.languages, id: \.self) {
                    Text(Locale.current.localizedString(forIdentifier: $0) ?? $0).tag($0)
                }
            }
            Toggle("Launch at login", isOn: Binding(
                get: { model.settings.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
        }
        .formStyle(.grouped)
    }
}
