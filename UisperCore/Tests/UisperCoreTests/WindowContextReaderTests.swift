import Foundation
import Testing
@testable import UisperCore

@MainActor
struct WindowContextReaderTests {
    @Test func takesTextBeforeCaretOnly() {
        #expect(WindowContextReader.tail(of: "hello world", beforeUTF16Offset: 5) == "hello")
    }

    @Test func caretUnknownUsesEndOfText() {
        #expect(WindowContextReader.tail(of: "one two", beforeUTF16Offset: nil, limit: 3) == "two")
    }

    @Test func limitsAndTrims() {
        #expect(WindowContextReader.tail(of: "aaaa bbbb ", beforeUTF16Offset: nil, limit: 5) == "bbbb")
        #expect(WindowContextReader.tail(of: "   ", beforeUTF16Offset: nil) == nil)
        #expect(WindowContextReader.tail(of: "", beforeUTF16Offset: 0) == nil)
    }

    @Test func caretOutOfRangeIsClamped() {
        #expect(WindowContextReader.tail(of: "abc", beforeUTF16Offset: 99) == "abc")
        #expect(WindowContextReader.tail(of: "abc", beforeUTF16Offset: -1) == nil)
    }

    @Test func countsUTF16LikeAccessibility() {
        // "😀" is two UTF-16 units; the caret after it and "ab" is at offset 4.
        #expect(WindowContextReader.tail(of: "😀ab cd", beforeUTF16Offset: 4) == "😀ab")
    }
}
