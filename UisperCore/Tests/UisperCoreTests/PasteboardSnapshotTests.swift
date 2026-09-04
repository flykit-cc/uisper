import AppKit
import Testing
@testable import UisperCore

@MainActor
struct PasteboardSnapshotTests {
    @Test func restoresPreviousString() {
        let pb = NSPasteboard(name: NSPasteboard.Name("uisper-test-\(UUID().uuidString)"))
        pb.clearContents(); pb.setString("before", forType: .string)
        let snap = PasteboardSnapshot.take(pb)
        pb.clearContents(); pb.setString("dictated", forType: .string)
        snap.restore(to: pb)
        #expect(pb.string(forType: .string) == "before")
    }

    @Test func restoresEmptyPasteboard() {
        let pb = NSPasteboard(name: NSPasteboard.Name("uisper-test-\(UUID().uuidString)"))
        pb.clearContents()
        let snap = PasteboardSnapshot.take(pb)
        pb.clearContents(); pb.setString("dictated", forType: .string)
        snap.restore(to: pb)
        #expect(pb.string(forType: .string) == nil)
    }
}
