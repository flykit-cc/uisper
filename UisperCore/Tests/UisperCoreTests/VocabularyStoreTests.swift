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

    @Test func oldStringArrayLoadsAsLearned() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(["the", "Claude Code"]).write(to: url)
        let v = VocabularyStore(fileURL: url)
        #expect(v.words == ["Claude Code", "the"])
        #expect(v.source(of: "the") == .learned)
    }

    @Test func sourcesSurviveARoundTrip() throws {
        let url = tempURL()
        let a = VocabularyStore(fileURL: url)
        a.add("flykit")
        a.add("Sinead", source: .learned)
        try a.save()
        let b = VocabularyStore(fileURL: url)
        #expect(b.source(of: "flykit") == .typed)
        #expect(b.source(of: "sinead") == .learned)
    }

    @Test func theOldestLearnedEntryIsEvictedAtTheCap() {
        let v = VocabularyStore(fileURL: tempURL())
        v.add("keepme")
        for i in 0..<(VocabularyStore.limit - 1) { v.add("learned\(i)", source: .learned) }
        v.add("newest", source: .learned)
        #expect(v.words.count == VocabularyStore.limit)
        #expect(!v.words.contains("learned0"))
        #expect(v.words.contains("keepme"))
        #expect(v.words.contains("newest"))
    }

    @Test func typedEntriesAreNeverRefused() {
        let v = VocabularyStore(fileURL: tempURL())
        for i in 0..<VocabularyStore.limit { v.add("typed\(i)") }
        v.add("dropped", source: .learned)
        v.add("extra")
        #expect(!v.words.contains("dropped"))
        #expect(v.words.contains("extra"))
    }
}
