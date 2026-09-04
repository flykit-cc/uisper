import SwiftUI
import UisperCore

struct CleanupTab: View {
    let model: AppModel
    @State private var newWord = ""

    var body: some View {
        Form {
            Section {
                Toggle("Fix grammar and punctuation with on-device AI", isOn: Bindable(model.settings).cleanupEnabled)
                if let notice = model.cleanupNotice { Text(notice).font(.callout).foregroundStyle(.secondary) }
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
