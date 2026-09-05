import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// A dictation hotkey: a key plus modifiers, or modifiers alone (e.g. Fn, or Right ⌥).
public struct Hotkey: Codable, Equatable, Sendable {
    /// nil means a modifier-only chord.
    public var keyCode: Int64?
    /// `CGEventFlags.rawValue` reduced to `Hotkey.modifierMask`.
    public var modifiers: UInt64

    public static let modifierMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift, .maskControl, .maskSecondaryFn]
    public static let optionSpace = Hotkey(keyCode: 49, modifiers: CGEventFlags.maskAlternate.rawValue)
    public static let fn = Hotkey(keyCode: nil, modifiers: CGEventFlags.maskSecondaryFn.rawValue)

    public init(keyCode: Int64?, modifiers: UInt64) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Hotkey.modifierMask.rawValue
    }

    public init(keyCode: Int64?, flags: CGEventFlags) {
        self.init(keyCode: keyCode, modifiers: flags.rawValue)
    }

    public var flags: CGEventFlags {
        CGEventFlags(rawValue: modifiers).intersection(Hotkey.modifierMask)
    }

    public var isModifierOnly: Bool { keyCode == nil }

    /// "⌥ Space", "⌘⇧D", "Fn", "F13", "⌃⌥ Right". A one-character key name joins the
    /// modifiers directly; a word is separated by a space.
    public var displayString: String {
        let f = flags
        var mods = ""
        if f.contains(.maskControl) { mods += "⌃" }
        if f.contains(.maskAlternate) { mods += "⌥" }
        if f.contains(.maskShift) { mods += "⇧" }
        if f.contains(.maskCommand) { mods += "⌘" }
        // Arrows, F-keys and the navigation cluster always carry the Fn flag, on the
        // NSEvent the recorder reads and on the CGEvent the tap reads. Matching keeps it;
        // the label hides it, so ⌃⌥ + Right reads "⌃⌥ Right" and not "⌃⌥Fn Right".
        let impliedFn = keyCode.map(Self.functionKeys.contains) ?? false
        if f.contains(.maskSecondaryFn), !impliedFn { mods += "Fn" }
        guard let keyCode else { return mods }
        let name = Self.keyName(keyCode)
        if mods.isEmpty { return name }
        return name.count == 1 ? mods + name : mods + " " + name
    }

    private static let specialNames: [Int64: String] = [
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Escape", 117: "Forward Delete",
        123: "Left", 124: "Right", 125: "Down", 126: "Up",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
    ]

    private static let functionKeys: Set<Int64> = [
        117, 123, 124, 125, 126, 115, 119, 116, 121,
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
        105, 107, 113, 106, 64, 79, 80, 90,
    ]

    private static func keyName(_ keyCode: Int64) -> String {
        specialNames[keyCode] ?? translated(keyCode) ?? "Key \(keyCode)"
    }

    /// The character the current ASCII-capable layout produces for this key, with no modifiers.
    private static func translated(_ keyCode: Int64) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        // The `kTISPropertyUnicodeKeyLayoutData` global is not Sendable under Swift 6, so the
        // key string is inlined instead.
        guard let raw = TISGetInputSourceProperty(source, "TISPropertyUnicodeKeyLayoutData" as CFString) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let name = String(utf16CodeUnits: chars, count: length).uppercased()
        return name.isEmpty ? nil : name
    }
}
