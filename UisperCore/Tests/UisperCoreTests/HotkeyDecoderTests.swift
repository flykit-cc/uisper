import CoreGraphics
import Testing
@testable import UisperCore

struct HotkeyDecoderTests {
    let space: Int64 = 49
    let escape: Int64 = 53
    let a: Int64 = 0

    @Test func optionSpacePressAndRelease() {
        var d = HotkeyDecoder(choice: .optionSpace)
        let down = d.handle(type: .keyDown, keyCode: space, flags: .maskAlternate)
        #expect(down.event == .pressed && down.swallow)
        #expect(d.isDown)
        let repeatDown = d.handle(type: .keyDown, keyCode: space, flags: .maskAlternate)
        #expect(repeatDown.event == nil && repeatDown.swallow)          // key repeat while held
        let up = d.handle(type: .keyUp, keyCode: space, flags: .maskAlternate)
        #expect(up.event == .released && up.swallow)
        #expect(!d.isDown)
    }

    @Test func plainSpaceIsIgnored() {
        var d = HotkeyDecoder(choice: .optionSpace)
        let r = d.handle(type: .keyDown, keyCode: space, flags: [])
        #expect(r.event == nil && !r.swallow)
    }

    @Test func releasingOptionWhileHeldReleases() {
        var d = HotkeyDecoder(choice: .optionSpace)
        _ = d.handle(type: .keyDown, keyCode: space, flags: .maskAlternate)
        let r = d.handle(type: .flagsChanged, keyCode: 58, flags: [])   // 58 = left option
        #expect(r.event == .released)
    }

    @Test func escapeWhileHeldCancels() {
        var d = HotkeyDecoder(choice: .optionSpace)
        _ = d.handle(type: .keyDown, keyCode: space, flags: .maskAlternate)
        let r = d.handle(type: .keyDown, keyCode: escape, flags: [])
        #expect(r.event == .cancelled && r.swallow)
        #expect(!d.isDown)
        let later = d.handle(type: .keyUp, keyCode: space, flags: .maskAlternate)
        #expect(later.event == nil)                                       // already cancelled
    }

    @Test func otherKeysPassThrough() {
        var d = HotkeyDecoder(choice: .optionSpace)
        _ = d.handle(type: .keyDown, keyCode: space, flags: .maskAlternate)
        let r = d.handle(type: .keyDown, keyCode: a, flags: [])
        #expect(r.event == nil && !r.swallow)
    }

    @Test func fnChoiceUsesFunctionFlag() {
        var d = HotkeyDecoder(choice: .fn)
        let down = d.handle(type: .flagsChanged, keyCode: 63, flags: .maskSecondaryFn)
        #expect(down.event == .pressed)
        let up = d.handle(type: .flagsChanged, keyCode: 63, flags: [])
        #expect(up.event == .released)
    }

    @Test func cancelSurvivesSpaceAutorepeat() {
        var d = HotkeyDecoder(choice: .optionSpace)
        _ = d.handle(type: .keyDown, keyCode: space, flags: .maskAlternate)
        let cancel = d.handle(type: .keyDown, keyCode: escape, flags: [])
        #expect(cancel.event == .cancelled && cancel.swallow)
        let repeatDown = d.handle(type: .keyDown, keyCode: space, flags: .maskAlternate)
        #expect(repeatDown.event == nil && repeatDown.swallow)      // autorepeat must not restart
        let up = d.handle(type: .keyUp, keyCode: space, flags: .maskAlternate)
        #expect(up.event == nil && up.swallow)                      // orphan keyUp swallowed
        let fresh = d.handle(type: .keyDown, keyCode: space, flags: .maskAlternate)
        #expect(fresh.event == .pressed && fresh.swallow)           // next press works again
    }

    @Test func releasingOptionAfterCancelClearsLatch() {
        var d = HotkeyDecoder(choice: .optionSpace)
        _ = d.handle(type: .keyDown, keyCode: space, flags: .maskAlternate)
        _ = d.handle(type: .keyDown, keyCode: escape, flags: [])
        let optionUp = d.handle(type: .flagsChanged, keyCode: 58, flags: [])
        #expect(optionUp.event == nil && !optionUp.swallow)          // no stray .released
        let fresh = d.handle(type: .keyDown, keyCode: space, flags: .maskAlternate)
        #expect(fresh.event == .pressed)                             // latch cleared
    }
}
