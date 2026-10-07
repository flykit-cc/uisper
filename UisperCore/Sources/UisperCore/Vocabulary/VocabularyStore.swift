import Foundation
import Observation

public enum VocabularySource: String, Codable, Sendable { case typed, learned }

/// The user's custom words, each tagged with where it came from, so learned guesses can be
/// evicted and typed words never are.
@MainActor
@Observable
public final class VocabularyStore {
    /// Roughly 800 tokens of names, which still leaves room in the smallest cleanup window.
    public static let limit = 200

    struct Entry: Codable, Equatable {
        var word: String
        var source: VocabularySource
        var added: Date
    }

    private var entries: [Entry] = [] { didSet { words = Self.sorted(entries) } }
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

    /// Reads the tagged format, or the older plain string array. Old entries load as learned
    /// because that is where nearly all of them came from, and only learned ones can be evicted.
    public func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let tagged = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = normalize(tagged)
        } else if let list = try? JSONDecoder().decode([String].self, from: data) {
            entries = normalize(list.map { Entry(word: $0, source: .learned, added: .distantPast) })
        }
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }

    /// At the cap, the oldest learned entry makes room. A word the user typed always goes in;
    /// a learned one is dropped when everything already there was typed.
    public func add(_ word: String, source: VocabularySource = .typed) {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty, index(of: w) == nil else { return }
        if entries.count >= Self.limit {
            let learned = entries.indices.filter { entries[$0].source == .learned }
            if let oldest = learned.min(by: { entries[$0].added < entries[$1].added }) {
                entries.remove(at: oldest)
            } else if source == .learned {
                return
            }
        }
        entries.append(Entry(word: w, source: source, added: Date()))
    }

    public func remove(_ word: String) {
        entries.removeAll { $0.word.caseInsensitiveCompare(word) == .orderedSame }
    }

    public func source(of word: String) -> VocabularySource? {
        index(of: word).map { entries[$0].source }
    }

    private func index(of word: String) -> Int? {
        entries.firstIndex { $0.word.caseInsensitiveCompare(word) == .orderedSame }
    }

    /// Trim, drop empties, dedupe case-insensitively (first spelling wins).
    private func normalize(_ list: [Entry]) -> [Entry] {
        var seen = Set<String>()
        var out: [Entry] = []
        for var entry in list {
            entry.word = entry.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !entry.word.isEmpty, seen.insert(entry.word.lowercased()).inserted else { continue }
            out.append(entry)
        }
        return out
    }

    static func sorted(_ entries: [Entry]) -> [String] {
        entries.map(\.word).sorted { $0.caseInsensitiveCompare($1) == .orderedAscending }
    }
}
