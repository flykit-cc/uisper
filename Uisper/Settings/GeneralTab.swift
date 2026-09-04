import SwiftUI
import UisperCore

struct GeneralTab: View {
    let model: AppModel

    var body: some View {
        Form {
            Picker("Hotkey", selection: Bindable(model.settings).hotkey) {
                Text("⌥ Space").tag(HotkeyChoice.optionSpace)
                Text("Fn / Globe (may clash with system dictation)").tag(HotkeyChoice.fn)
            }
            .onChange(of: model.settings.hotkey) { _, _ in model.hotkeyChoiceChanged() }
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
