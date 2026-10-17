import Foundation
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers
import UisperCore
import os

/// Decider 4B v2 on MLX, answering word-pick questions by reading the option-letter logits at the
/// answer slot. Nothing is generated.
///
/// The prompt layout and tokenization copy the model's own `prompt.py` (`build`, plain layout):
/// "Context:\n…" and the question part are tokenized separately and concatenated, no special tokens.
///
/// The model state after the header (the vocabulary line, which changes only when the vocabulary does)
/// is kept. Every question of a dictation then runs on a copy of it: the tokens all questions share
/// once, the rest in one padded pass. Each question carries its own context, because past 30 words a
/// spot's context is only its sentence.
actor MLXDecider: DecisionModel {
    struct NotInstalled: Error {}
    static let letters = Array("ABCDEFGHIJ").map(String.init)

    /// The model state after reading `ids`. Never changed once built: every pass works on a copy.
    /// Unchecked: the caches are only touched inside `ModelContainer.perform`, which runs one call at a time.
    private final class State: @unchecked Sendable {
        let ids: [Int]
        let cache: [KVCache]
        init(ids: [Int], cache: [KVCache]) { self.ids = ids; self.cache = cache }
    }

    private let directory: URL
    private let log = Logger(subsystem: "cc.flykit.uisper", category: "decider")
    private var model: ModelContainer?
    private var loading: Task<ModelContainer, Error>?
    private var afterHeader: State?

    init(directory: URL = defaultDirectory()) { self.directory = directory }

    static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("uisper/Models/decider-4b-v2-4bit", isDirectory: true)
    }

    static func isInstalled(_ directory: URL) -> Bool {
        ["config.json", "model.safetensors", "tokenizer.json", "decider_config.json"].allSatisfy {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }

    /// Loads the weights, compiles the Metal kernels and reads the header, so the first dictation
    /// pays for none of it.
    func prewarm(header: String) async {
        do {
            let container = try await container()
            let cached = afterHeader
            afterHeader = try await container.perform { ctx in
                Self.state(after: Self.encode("Context:\n" + header, ctx.tokenizer), from: cached, ctx.model)
            }
        } catch { log.error("prewarm failed: \(error.localizedDescription, privacy: .public)") }
    }

    func decide(header: String, questions: [(context: String, question: String, options: [String])]) async throws -> [[Double]] {
        guard Self.isInstalled(directory) else { throw NotInstalled() }
        guard !questions.isEmpty else { return [] }
        let container = try await container()
        let temperature = Float(try Self.temperature(directory))
        let cachedHeader = afterHeader
        let (p, h) = try await container.perform { ctx -> ([[Double]], State) in
            let tok = ctx.tokenizer
            let h = Self.state(after: Self.encode("Context:\n" + header, tok), from: cachedHeader, ctx.model)
            // Each context is tokenized whole with the header, as the model was trained. The header's
            // state applies only when its tokens come out as a true prefix, as they did in every 2026-10-17 case.
            var rows: [[Int]] = []
            for q in questions {
                let ids = Self.encode("Context:\n" + header + q.context, tok)
                guard ids.starts(with: h.ids) else { throw HeaderMismatch() }
                rows.append(Array(ids.dropFirst(h.ids.count)) + Self.encode(Self.questionText(q.question, q.options), tok))
            }
            // What all rows share (the whole dictation, when it is short) is read once; each row keeps at
            // least its last token for the batched pass, which is where the answer is read.
            var shared = rows.dropFirst().reduce(rows[0]) { common, row in Array(zip(common, row).prefix { $0 == $1 }.map(\.0)) }
            shared = Array(shared.prefix(rows.map(\.count).min()! - 1))
            let cache = h.cache.map { $0.copy() }
            if !shared.isEmpty {
                _ = ctx.model(MLXArray(shared.map(Int32.init)).expandedDimensions(axis: 0), cache: cache)
                eval(cache.flatMap(\.state))
            }
            let rest = rows.map { Array($0.dropFirst(shared.count)) }
            // Right-padded. No mask needed: every layer is causal, so padding after a row's last token cannot reach it.
            let width = rest.map(\.count).max()!
            let pad = tok.eosTokenId ?? 0
            let x = MLXArray(rest.flatMap { $0 + Array(repeating: pad, count: width - $0.count) }.map(Int32.init))
                .reshaped([rest.count, width])
            let logits = ctx.model(x, cache: Self.copies(of: cache, rest.count, ctx.model))
            let letterIDs = MLXArray(Self.letters.map { Int32(Self.encode($0, tok)[0]) })
            let slots = take(stacked(rest.indices.map { logits[$0, rest[$0].count - 1] }), letterIDs, axis: -1).asType(.float32)
            eval(slots)
            let p = questions.indices.map { i in
                softmax(slots[i, ..<questions[i].options.count] / temperature, axis: -1).asArray(Float.self).map(Double.init)
            }
            return (p, h)
        }
        afterHeader = h
        return p
    }

    /// A dictation whose first characters merge with the header's last token; word pick leaves it alone.
    struct HeaderMismatch: Error {}

    static func questionText(_ question: String, _ options: [String]) -> String {
        "\n\nQuestion: \(question)\nOptions:"
            + options.enumerated().map { "\n(\(letters[$0.offset])) \($0.element)" }.joined()
            + "\nAnswer: ("
    }

    /// `n` independent copies of a state, stacked along the batch axis.
    private static func copies(of cache: [KVCache], _ n: Int, _ model: any LanguageModel) -> [KVCache] {
        guard n > 1 else { return cache.map { $0.copy() } }
        let out = model.newCache(parameters: nil)
        for (var c, base) in zip(out, cache) {
            c.state = base.state.map { repeated($0, count: n, axis: 0) }
        }
        return out
    }

    private static func encode(_ text: String, _ tokenizer: any MLXLMCommon.Tokenizer) -> [Int] {
        tokenizer.encode(text: text, addSpecialTokens: false)
    }

    /// `cached` when it already holds `ids`, else a fresh state after reading them.
    private static func state(after ids: [Int], from cached: State?, _ model: any LanguageModel) -> State {
        if let cached, cached.ids == ids { return cached }
        let cache = model.newCache(parameters: nil)
        _ = model(MLXArray(ids.map(Int32.init)).expandedDimensions(axis: 0), cache: cache)
        // Only the cache, never the logits: MLX is lazy, so the vocabulary-wide head is never computed.
        eval(cache.flatMap(\.state))
        return State(ids: ids, cache: cache)
    }

    private func container() async throws -> ModelContainer {
        if let model { return model }
        if let loading { return try await loading.value }
        let task = Task { [directory, log] in
            let started = ContinuousClock.now
            let m = try await loadModelContainer(from: directory, using: #huggingFaceTokenizerLoader())
            log.info("decider loaded in \(ContinuousClock.now - started, privacy: .public)")
            return m
        }
        loading = task
        defer { loading = nil }
        let m = try await task.value
        model = m
        return m
    }

    /// The temperature the model card serves a plain choice question at.
    static func temperature(_ directory: URL) throws -> Double {
        let data = try Data(contentsOf: directory.appendingPathComponent("decider_config.json"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let byType = json["temperature_by_type"] as? [String: Any]
        guard let t = (byType?["choice"] as? Double) ?? (json["temperature"] as? Double) else { throw NotInstalled() }
        return t
    }
}
