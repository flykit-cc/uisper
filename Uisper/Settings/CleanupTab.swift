import SwiftUI
import UisperCore

struct CleanupTab: View {
    let model: AppModel
    @State private var newWord = ""

    var body: some View {
        Form {
            Section {
                Toggle("Fix grammar and punctuation with on-device AI", isOn: Bindable(model.settings).cleanupEnabled)
                Picker("Model", selection: Bindable(model.settings).cleanupEngine) {
                    Text("Built-in (Qwen3 4B on MLX)").tag(CleanupEngine.builtIn)
                    Text("Apple Intelligence").tag(CleanupEngine.apple)
                }
                .disabled(!model.settings.cleanupEnabled)
                .onChange(of: model.settings.cleanupEngine) { model.ensureModel() }
                .onChange(of: model.settings.cleanupEnabled) { model.ensureModel() }
                if let notice = model.cleanupNotice {
                    HStack {
                        Text(notice).font(.callout).foregroundStyle(.secondary)
                        if case .failed = model.modelDownload.state { Button("Retry") { model.ensureModel() } }
                    }
                }
            }
            Section("Vocabulary") {
                HStack {
                    TextField("Add a word or name", text: $newWord).onSubmit(add)
                    Button("Add", action: add).disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                List(model.vocabulary.words, id: \.self) { word in
                    HStack {
                        Text(word)
                        Spacer()
                        Button(role: .destructive) { model.vocabulary.remove(word); model.saveVocabulary() } label: {
                            Image(systemName: "minus.circle")
                        }.buttonStyle(.borderless)
                    }
                }
                .frame(minHeight: 140)
            }
        }
        .formStyle(.grouped)
    }

    private func add() {
        model.vocabulary.add(newWord)
        model.saveVocabulary()
        newWord = ""
    }
}
