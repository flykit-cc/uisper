import Combine
import SwiftUI
import UisperCore

struct PermissionsTab: View {
    @State private var status: [Permission: Bool] = [:]
    // Stored once: a publisher created inside `body` is replaced on every render and never fires.
    private let ticker = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    private let becameActive = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)

    var body: some View {
        Form {
            ForEach(Permission.allCases, id: \.self) { p in
                HStack(alignment: .top) {
                    Image(systemName: status[p] == true ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(status[p] == true ? .green : .secondary)
                    VStack(alignment: .leading) {
                        Text(p.title).bold()
                        Text(p.why).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if status[p] != true {
                        Button("Grant") { Task { _ = await Permissions.request(p); refresh() } }
                        Button("Open Settings") { Permissions.openSystemSettings(p) }
                    }
                }
            }
            Text("Restart uisper after granting Accessibility or Input Monitoring.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onReceive(ticker) { _ in refresh() }
        .onReceive(becameActive) { _ in refresh() }   // the user comes back from System Settings
    }

    private func refresh() {
        for p in Permission.allCases { status[p] = Permissions.status(p) }
    }
}
