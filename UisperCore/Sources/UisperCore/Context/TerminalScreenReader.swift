import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os

/// Reads what is on screen in a terminal, which does not expose its text to Accessibility.
///
/// Ghostty ships a binding that writes the visible screen to a temporary file and puts the
/// *path* on the clipboard. That is far better than selecting and copying: nothing is left
/// selected, and the user's terminal content never touches the pasteboard — only a short path.
///
/// Used only for learning corrections, never for cleanup context: it costs a synthetic
/// keystroke and a temp file, which is worth it to learn a word and not worth it to match tone.
@MainActor
public enum TerminalScreenReader {
    /// Terminals that can hand over their screen, and the key that asks for it.
    /// Ghostty's default `super+ctrl+shift+j` is `write_screen_file:copy,plain`.
    static let bindings: [String: (key: Int, flags: CGEventFlags)] = [
        "com.mitchellh.ghostty": (kVK_ANSI_J, [.maskCommand, .maskControl, .maskShift]),
    ]

    /// How long to wait for the terminal to write the file and update the clipboard.
    static let timeout: Duration = .milliseconds(600)
    private static let log = Logger(subsystem: "cc.flykit.uisper", category: "terminal")

    public static func supports(_ bundleID: String?) -> Bool {
        bundleID.map { bindings[$0] != nil } ?? false
    }

    /// The visible screen, or nil when this app cannot provide it or did not in time.
    public static func screenText(bundleID: String?) async -> String? {
        guard let bundleID, let binding = bindings[bundleID] else { return nil }
        // Secure input blocks synthetic events anyway, and a password field is the last place
        // to be pressing keys and reading files.
        guard !IsSecureEventInputEnabled() else { return nil }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.take(pasteboard)
        let before = pasteboard.changeCount
        defer { snapshot.restore(to: pasteboard) }

        guard post(key: binding.key, flags: binding.flags) else { return nil }

        guard let path = await pathFromPasteboard(pasteboard, changedFrom: before) else {
            log.info("terminal screen: no path on the clipboard within \(timeout, privacy: .public)")
            return nil
        }
        defer { try? FileManager.default.removeItem(atPath: path) }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        // The whole screen, not just its tail: in a chat TUI the input line sits above a border
        // and a status row, and a small tail window can cut it off. An older copy of the same
        // sentence higher up is handled by the matcher preferring the most recent match.
        return text.isEmpty ? nil : text
    }

    /// Polls until the terminal replaces the clipboard with a path to a file that exists.
    private static func pathFromPasteboard(_ pasteboard: NSPasteboard, changedFrom before: Int) async -> String? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(25))
            guard pasteboard.changeCount != before,
                  let value = pasteboard.string(forType: .string) else { continue }
            let path = value.trimmingCharacters(in: .whitespacesAndNewlines)
            // Only ever a path we can read: anything else is the user's own clipboard racing us.
            if path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    private static func post(key: Int, flags: CGEventFlags) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: false)
        else { return false }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
