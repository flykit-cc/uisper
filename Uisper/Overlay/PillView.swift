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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 440, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.08)))
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

/// Five bars that scale with the mic level.
struct LevelMeter: View {
    let level: Float
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(.primary)
                    .frame(width: 3, height: 6 + CGFloat(min(1, max(0, level * 3 - Float(i) * 0.15))) * 14)
            }
        }
        .frame(width: 28, height: 20)
        .animation(.linear(duration: 0.05), value: level)
    }
}
