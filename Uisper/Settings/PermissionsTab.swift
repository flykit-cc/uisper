import Combine
import SwiftUI
import UisperCore

struct PermissionsTab: View {
    @State private var status: [Permission: Bool] = [:]

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
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in refresh() }
    }

    private func refresh() {
        for p in Permission.allCases { status[p] = Permissions.status(p) }
    }
}
