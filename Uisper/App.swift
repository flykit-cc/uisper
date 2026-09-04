import SwiftUI
import UisperCore

@main
struct UisperApp: App {
    var body: some Scene {
        MenuBarExtra("uisper", systemImage: "mic") {
            Text("uisper \(UisperCore.version)")
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
