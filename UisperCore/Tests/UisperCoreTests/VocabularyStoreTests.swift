import Foundation
import Testing
@testable import UisperCore

@MainActor
struct VocabularyStoreTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("uisper-vocab-\(UUID().uuidString)")
            .appendingPathComponent("vocabulary.json")
    }

    @Test func startsEmptyWhenFileMissing() {
        let v = VocabularyStore(fileURL: tempURL())
        #expect(v.words.isEmpty)
    }

    @Test func addDedupesTrimsAndSorts() {
        let v = VocabularyStore(fileURL: tempURL())
        v.add("  Zephyr ")
        v.add("zephyr")
        v.add("Kubernetes")
        #expect(v.words == ["Kubernetes", "Zephyr"])
    }

    @Test func saveThenLoadRoundTrips() throws {
        let url = tempURL()
        let a = VocabularyStore(fileURL: url)
        a.add("uisper"); a.add("FlyKit")
        try a.save()
        let b = VocabularyStore(fileURL: url)
        #expect(b.words == ["FlyKit", "uisper"])
        b.remove("FlyKit")
        #expect(b.words == ["uisper"])
    }
}
