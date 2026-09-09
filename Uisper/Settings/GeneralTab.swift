import SwiftUI
import UisperCore

struct GeneralTab: View {
    let model: AppModel

    var body: some View {
        Form {
            LabeledContent("Hotkey") {
                VStack(alignment: .leading, spacing: 4) {
                    HotkeyRecorderView(hotkey: Bindable(model.settings).hotkey, model: model)
                    Text("Click the field, then press your shortcut. Esc cancels, ⌫ resets to ⌥ Space.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .onChange(of: model.settings.hotkey) { _, _ in model.hotkeyChanged() }
            Picker("Mode", selection: Bindable(model.settings).mode) {
                Text("Hold to talk").tag(ActivationMode.hold)
                Text("Press to toggle").tag(ActivationMode.toggle)
            }
            LabeledContent("Speech engine") {
                VStack(alignment: .leading, spacing: 4) {
                    Picker("", selection: Bindable(model.settings).engine) {
                        Text("Apple").tag(EngineID.apple)
                        Text("Parakeet").tag(EngineID.parakeet)
                    }
                    .labelsHidden()
                    Text(model.settings.engine == .apple
                         ? "Built into macOS. Shows words as you speak."
                         : "Parakeet on the Neural Engine. Usually more accurate, but the text only appears after you let go. Choosing it downloads about 600 MB now.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let notice = model.speechNotice {
                        HStack(spacing: 6) {
                            if case .downloading(let fraction, _, _) = model.speechDownload.state {
                                ProgressView(value: fraction).frame(width: 90)
                            } else if case .compiling = model.speechDownload.state {
                                ProgressView().controlSize(.small)
                            }
                            Text(notice).font(.caption)
                        }
                        .foregroundStyle(model.speechDownload.state.isFailure ? .red : .secondary)
                    }
                }
            }
            .onChange(of: model.settings.engine) { model.ensureSpeechModel() }
            Picker("Language", selection: Bindable(model.settings).languageID) {
                ForEach(model.settings.languages, id: \.self) {
                    Text(Locale.current.localizedString(forIdentifier: $0) ?? $0).tag($0)
                }
            }
            .onChange(of: model.settings.languageID) { model.ensureSpeechModel() }
            Toggle("Launch at login", isOn: Binding(
                get: { model.settings.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            LabeledContent("Diagnostics") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Log transcripts", isOn: Bindable(model.settings).debugLogging)
                    Text("Writes what was heard and what was cleaned to the macOS log, to compare them. Off by default — it records your dictated text.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
