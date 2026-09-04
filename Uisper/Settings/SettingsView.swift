import SwiftUI
import UisperCore

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            GeneralTab(model: model).tabItem { Label("General", systemImage: "gear") }
            CleanupTab(model: model).tabItem { Label("Cleanup", systemImage: "sparkles") }
            PermissionsTab().tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 480, height: 360)
    }
}
