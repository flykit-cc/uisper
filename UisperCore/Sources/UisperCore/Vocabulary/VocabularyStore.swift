import Foundation
import Observation

/// The user's custom words. Persisted as a JSON array of strings.
@MainActor
@Observable
public final class VocabularyStore {
    public private(set) var words: [String] = []
    public let fileURL: URL

    public static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("uisper", isDirectory: true).appendingPathComponent("vocabulary.json")
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    public func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return }
        words = normalize(list)
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(words)
        try data.write(to: fileURL, options: .atomic)
    }

    public func add(_ word: String) {
        words = normalize(words + [word])
    }

    public func remove(_ word: String) {
        words.removeAll { $0.caseInsensitiveCompare(word) == .orderedSame }
    }

    /// Trim, drop empties, dedupe case-insensitively (first spelling wins), sort case-insensitively.
    private func normalize(_ list: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in list {
            let w = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !w.isEmpty, seen.insert(w.lowercased()).inserted else { continue }
            out.append(w)
        }
        return out.sorted { $0.caseInsensitiveCompare($1) == .orderedAscending }
    }
}
