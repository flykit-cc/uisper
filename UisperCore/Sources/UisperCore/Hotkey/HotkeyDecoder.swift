import CoreGraphics

public enum HotkeyEvent: Sendable, Equatable { case pressed, released, cancelled }

/// Pure state machine turning raw key events into hotkey events. Testable without an event tap.
public struct HotkeyDecoder: Sendable {
    public var choice: HotkeyChoice
    public private(set) var isDown = false
    /// Set by an Escape cancel, cleared when the hotkey is physically let go. Stops Space
    /// autorepeat from restarting a dictation the user just cancelled.
    private var cancelled = false

    private static let space: Int64 = 49
    private static let escape: Int64 = 53

    public init(choice: HotkeyChoice) { self.choice = choice }

    public mutating func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> (event: HotkeyEvent?, swallow: Bool) {
        if isDown, type == .keyDown, keyCode == Self.escape {
            isDown = false
            cancelled = true
            return (.cancelled, true)
        }
        switch choice {
        case .optionSpace:
            let isChord = keyCode == Self.space && flags.contains(.maskAlternate)
            switch type {
            case .keyDown where isChord:
                if isDown || cancelled { return (nil, true) }
                isDown = true
                return (.pressed, true)
            case .keyUp where keyCode == Self.space:
                if cancelled { cancelled = false; return (nil, true) }
                guard isDown else { return (nil, false) }
                isDown = false
                return (.released, true)
            case .flagsChanged where isDown && !flags.contains(.maskAlternate):
                isDown = false
                return (.released, false)
            default:
                return (nil, false)
            }
        case .fn:
            guard type == .flagsChanged else { return (nil, false) }
            let fnDown = flags.contains(.maskSecondaryFn)
            if fnDown, !isDown, !cancelled { isDown = true; return (.pressed, false) }
            if !fnDown {
                cancelled = false
                if isDown { isDown = false; return (.released, false) }
            }
            return (nil, false)
        }
    }
}
