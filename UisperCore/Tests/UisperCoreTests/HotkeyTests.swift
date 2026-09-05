import CoreGraphics
import Testing
@testable import UisperCore

struct HotkeyTests {
    @Test func displayStringOptionSpace() {
        #expect(Hotkey.optionSpace.displayString == "⌥ Space")
    }

    @Test func displayStringFn() {
        #expect(Hotkey.fn.displayString == "Fn")
    }

    /// keyCode 2 is "D" on a US layout. Assert the shape, not the letter, so the test
    /// survives a different keyboard layout on the build machine. Modifiers use the macOS
    /// menu order ⌃⌥⇧⌘, so ⌘ + ⇧ reads "⇧⌘".
    @Test func displayStringLetterUppercased() {
        let s = Hotkey(keyCode: 2, flags: [.maskCommand, .maskShift]).displayString
        #expect(s.hasPrefix("⇧⌘"))
        #expect(s.count == 3)
        #expect(s.last?.isUppercase == true)
    }

    /// AppKit sets the Fn flag for arrows and F-keys. The label must not show it.
    @Test func displayStringHidesImpliedFn() {
        #expect(Hotkey(keyCode: 124, flags: [.maskControl, .maskAlternate, .maskSecondaryFn]).displayString == "⌃⌥ Right")
        #expect(Hotkey(keyCode: 105, flags: .maskSecondaryFn).displayString == "F13")
    }
}
