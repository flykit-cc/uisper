import SwiftUI
import UisperCore

struct PillView: View {
    let session: DictationSession

    var body: some View {
        HStack(spacing: 12) {
            leading
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 440, alignment: .leading)
        .font(.system(size: 14, weight: .medium, design: .rounded))
        .glassEffect(.regular, in: Capsule())
        .overlay(Capsule().strokeBorder(
            LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
            lineWidth: 0.8))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .padding(24)   // room for the shadow inside the borderless panel
        .animation(.easeOut(duration: 0.15), value: session.state)
    }

    @ViewBuilder private var leading: some View {
        switch session.state {
        case .listening:
            LevelMeter(level: session.audioLevel)
        case .polishing:
            ProgressView().controlSize(.small)
        case .inserted(let result):
            if case .copiedOnly = result {
                Image(systemName: "doc.on.clipboard").foregroundStyle(.secondary)
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder private var content: some View {
        switch session.state {
        case .listening(let text, let volatile):
            if text.isEmpty && volatile.isEmpty {
                Text("Listening…").foregroundStyle(.secondary)
            } else {
                (Text(text) + Text(text.isEmpty ? "" : " ") + Text(volatile).foregroundStyle(.secondary))
                    .lineLimit(3)
                    .truncationMode(.head)
            }
        case .polishing:
            Text("Polishing…").foregroundStyle(.secondary)
        case .inserted(let result):
            if case .copiedOnly(let reason) = result { Text(reason) } else { Text("Inserted") }
        case .error(let message):
            Text(message)
        case .idle:
            EmptyView()
        }
    }
}

/// Five bars that dance with the mic level. Speech RMS is tiny (0.01–0.1), so use a dB scale.
struct LevelMeter: View {
    let level: Float
    private static let weights: [CGFloat] = [0.55, 0.8, 1, 0.8, 0.55]

    private var normalized: CGFloat {
        let db = 20 * log10(max(Double(level), 1e-5))          // -100 … 0
        return CGFloat(min(1, max(0, (db + 58) / 34)))          // -58 dB → 0, -24 dB → 1
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(Color.accentColor.gradient)
                    .frame(width: 3, height: 3 + normalized * Self.weights[i] * 24)
            }
        }
        .frame(width: 28, height: 28)
        .animation(.easeOut(duration: 0.06), value: normalized)
    }
}
