import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os

public enum InsertionResult: Sendable, Equatable {
    case inserted                    // written via Accessibility
    case pasted                      // written via ⌘V
    case copiedOnly(reason: String)  // left on the clipboard, nothing typed
}

@MainActor
public protocol TextInserting: AnyObject {
    func insert(_ text: String) async -> InsertionResult
}

/// Puts text into the focused app: Accessibility first, paste fallback, clipboard-only last.
@MainActor
public final class TextInserter: TextInserting {
    private let log = Logger(subsystem: "cc.flykit.uisper", category: "insert")

    public init() {}

    public func insert(_ text: String) async -> InsertionResult {
        guard !text.isEmpty else { return .copiedOnly(reason: "Nothing to insert.") }
        if IsSecureEventInputEnabled() {
            copy(text)
            return .copiedOnly(reason: "Secure input is on. Text copied to the clipboard.")
        }
        if insertViaAccessibility(text) { return .inserted }
        return await paste(text)
    }

    /// Frontmost app and its focused window title, for the cleaner's tone hint.
    public func focusedContext() -> AppContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        var title: String?
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var window: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &window) == .success,
           let window {
            var t: AnyObject?
            // swiftlint:disable:next force_cast
            if AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &t) == .success {
                title = t as? String
            }
        }
        return AppContext(bundleID: app.bundleIdentifier, appName: app.localizedName, windowTitle: title)
    }

    // MARK: - Accessibility

    private func insertViaAccessibility(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return false }
        // swiftlint:disable:next force_cast
        let element = focused as! AXUIElement
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success else {
            return false
        }
        // Chrome and Electron report success without writing. Verify.
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let current = value as? String, current.contains(text) else {
            log.info("AX write not verified, falling back to paste")
            return false
        }
        return true
    }

    // MARK: - Paste

    private func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func paste(_ text: String) async -> InsertionResult {
        let pb = NSPasteboard.general
        let snapshot = PasteboardSnapshot.take(pb)
        copy(text)
        guard postCommandV() else {
            return .copiedOnly(reason: "Could not send ⌘V. Text copied to the clipboard.")
        }
        try? await Task.sleep(for: .milliseconds(200))
        snapshot.restore(to: pb)
        return .pasted
    }

    private func postCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
