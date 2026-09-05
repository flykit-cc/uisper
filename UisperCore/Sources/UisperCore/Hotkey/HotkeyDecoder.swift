import CoreGraphics

public enum HotkeyEvent: Sendable, Equatable { case pressed, released, cancelled }

/// Pure state machine turning raw key events into hotkey events. Testable without an event tap.
public struct HotkeyDecoder: Sendable {
    public var hotkey: Hotkey
    public private(set) var isDown = false
    /// Set by an Escape cancel, cleared when the hotkey is physically let go. Stops Space
    /// autorepeat from restarting a dictation the user just cancelled.
    private var cancelled = false

    private static let escape: Int64 = 53

    public init(hotkey: Hotkey) { self.hotkey = hotkey }

    public mutating func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> (event: HotkeyEvent?, swallow: Bool) {
        if isDown, type == .keyDown, keyCode == Self.escape {
            isDown = false
            cancelled = true
            return (.cancelled, true)
        }
        let masked = flags.intersection(Hotkey.modifierMask)
        let wanted = hotkey.flags

        guard let hotkeyCode = hotkey.keyCode else {
            // A modifier-only chord with no modifiers would fire on every flagsChanged.
            // The recorder never produces one; corrupted defaults could.
            guard type == .flagsChanged, !wanted.isEmpty else { return (nil, false) }
            if masked == wanted, !isDown, !cancelled {
                isDown = true
                return (.pressed, false)
            }
            if !masked.isSuperset(of: wanted), isDown || cancelled {
                let wasDown = isDown
                isDown = false
                cancelled = false
                return (wasDown ? .released : nil, false)
            }
            return (nil, false)
        }

        switch type {
        case .keyDown where keyCode == hotkeyCode && masked == wanted:
            if isDown || cancelled { return (nil, true) }
            isDown = true
            return (.pressed, true)
        case .keyUp where keyCode == hotkeyCode:
            if cancelled { cancelled = false; return (nil, true) }
            guard isDown else { return (nil, false) }
            isDown = false
            return (.released, true)
        case .flagsChanged where isDown && !masked.isSuperset(of: wanted):
            isDown = false
            return (.released, false)
        default:
            return (nil, false)
        }
    }
}
