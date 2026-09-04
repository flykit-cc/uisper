import SwiftUI
import UisperCore

@main
struct UisperApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            MenuBarLabel(model: model, systemImage: menuIcon)
        }
        Settings {
            SettingsView(model: model)
        }
    }

    private var menuIcon: String {
        switch model.session.state {
        case .listening: return "mic.fill"
        case .polishing: return "sparkles"
        default: return "mic"
        }
    }
}
