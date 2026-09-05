import AppKit
import CoreGraphics
import SwiftUI
import UisperCore

/// A click-then-press shortcut field. Click it, press any combination, and that becomes the
/// hotkey. Keys arrive through the global event tap (so F14/F15 work too). Esc cancels, ⌫ resets.
struct HotkeyRecorderView: View {
    @Binding var hotkey: Hotkey
    let model: AppModel
    @State private var recording = false
    @State private var lastModifiers: CGEventFlags = []

    var body: some View {
        Button(action: { recording ? stop() : start() }) {
            Text(recording ? "Type shortcut…" : hotkey.displayString)
                .foregroundStyle(recording ? .secondary : .primary)
                .frame(maxWidth: .infinity, minHeight: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 5)
            .strokeBorder(recording ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: recording ? 2 : 1))
        .onDisappear(perform: stop)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stop() }
    }

    private func start() {
        recording = true
        lastModifiers = []
        model.setHotkeyRecording { type, keyCode, flags in handle(type: type, keyCode: keyCode, flags: flags) }
    }

    private func stop() {
        guard recording else { return }
        recording = false
        model.setHotkeyRecording(nil)
    }

    /// Returns true when the event must be swallowed.
    private func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        switch type {
        case .keyDown:
            switch keyCode {
            case 53: break                                   // Esc: cancel
            case 51: hotkey = .optionSpace                   // ⌫: reset
            default: hotkey = Hotkey(keyCode: keyCode, flags: flags)
            }
            stop()
            return true
        case .keyUp:
            return true
        case .flagsChanged:
            if flags.isEmpty, !lastModifiers.isEmpty {       // all modifiers released, no key pressed
                hotkey = Hotkey(keyCode: nil, flags: lastModifiers)
                stop()
            }
            lastModifiers = flags
            return false
        default:
            return false
        }
    }
}
