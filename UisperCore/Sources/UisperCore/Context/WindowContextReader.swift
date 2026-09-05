import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Reads what the user is typing into: app, window title and the text just before the caret.
/// Called once per dictation, after the hotkey is released, never inside the event tap.
@MainActor
public struct WindowContextReader {
    /// Enough for tone, names and the current sentence; small enough to stay inside the model window.
    public static let textLimit = 600

    public init() {}

    public func read() -> AppContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var title: String?
        if let window = attribute(appElement, kAXFocusedWindowAttribute) {
            // swiftlint:disable:next force_cast
            title = attribute(window as! AXUIElement, kAXTitleAttribute) as? String
        }
        return AppContext(bundleID: app.bundleIdentifier, appName: app.localizedName,
                          windowTitle: title, surroundingText: textBeforeCaret())
    }

    /// Up to `textLimit` characters before the caret of the focused text element, or nil when the
    /// app hides its text (Chrome, Electron) or the field is secure.
    private func textBeforeCaret() -> String? {
        guard !IsSecureEventInputEnabled(),
              let focused = attribute(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute) else { return nil }
        // swiftlint:disable:next force_cast
        let element = focused as! AXUIElement
        guard attribute(element, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,
              let value = attribute(element, kAXValueAttribute) as? String else { return nil }
        var caret: Int?
        if let rangeValue = attribute(element, kAXSelectedTextRangeAttribute) {
            var range = CFRange()
            // swiftlint:disable:next force_cast
            if AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) { caret = range.location }
        }
        return Self.tail(of: value, beforeUTF16Offset: caret)
    }

    /// The last `limit` characters before `offset` (UTF-16 units, as Accessibility counts them).
    /// No offset means the caret position is unknown, so the end of the text is used.
    static func tail(of text: String, beforeUTF16Offset offset: Int?, limit: Int = textLimit) -> String? {
        let utf16 = text.utf16
        let end = min(max(offset ?? utf16.count, 0), utf16.count)
        let start = max(end - limit, 0)
        let s = utf16.index(utf16.startIndex, offsetBy: start)
        let e = utf16.index(utf16.startIndex, offsetBy: end)
        // Decoding by units tolerates a cut inside a surrogate pair (one replacement character at the edge).
        let piece = String(decoding: Array(utf16[s..<e]), as: UTF16.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return piece.isEmpty ? nil : piece
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
