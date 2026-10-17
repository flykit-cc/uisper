import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXNN

extension ModelDownload {
    /// Decider is published only in bf16 (7.8 GB), so the full weights come from its author and this Mac
    /// makes the 4-bit copy uisper loads, then deletes the download.
    static func decider(target: URL = MLXDecider.defaultDirectory()) -> ModelDownload {
        let download = target.deletingLastPathComponent().appendingPathComponent("decider-4b-v2-bf16", isDirectory: true)
        let source = Source(
            // The v2 tag, not main: the 4-bit copy and the word-pick threshold were tuned on this version.
            baseURL: URL(string: "https://huggingface.co/Mapika/decider-4b/resolve/v2/")!,
            files: ["config.json", "model.safetensors", "tokenizer.json", "tokenizer_config.json",
                    "decider_config.json", "generation_config.json", "chat_template.jinja"],
            sizeLabel: "7.8 GB download, 2.2 GB on disk")
        return ModelDownload(source, directory: download, isReady: { MLXDecider.isInstalled(target) }) {
            try await quantizeDecider(from: download, to: target, files: source.files)
        }
    }

    /// Does what `mlx_lm.convert -q` (0.31) does for this model: the loader's own weight cleanup, every
    /// Linear and Embedding quantized at group size 64 and 4 bits, and the same `quantization` block in
    /// config.json, so the copy loads and scores like one made in Python.
    /// Holds the bf16 weights in memory while it runs, about 8 GB: fine on Apple silicon with 16 GB or more.
    nonisolated static func quantizeDecider(from download: URL, to target: URL, files: [String]) async throws {
        let fm = FileManager.default
        let configURL = download.appendingPathComponent("config.json")
        guard var config = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: configURL.path])
        }
        // The weights are named `model.language_model.*`, which only mlx-swift-lm's `qwen3_5` loader accepts.
        config["model_type"] = "qwen3_5"
        let model = try await LLMTypeRegistry.shared.createModel(
            configuration: JSONSerialization.data(withJSONObject: config), modelType: "qwen3_5")
        try loadWeights(modelDirectory: download, model: model)
        quantize(model: model, groupSize: 64, bits: 4, mode: .affine)
        let quantization: [String: Any] = ["group_size": 64, "bits": 4, "mode": "affine"]
        config["quantization"] = quantization
        config["quantization_config"] = quantization

        // Built beside the target and moved in whole, so a crash never leaves a half-written model that looks installed.
        let partial = target.appendingPathExtension("partial")
        try? fm.removeItem(at: partial)
        try fm.createDirectory(at: partial, withIntermediateDirectories: true)
        try save(arrays: Dictionary(uniqueKeysWithValues: model.parameters().flattened()), metadata: ["format": "mlx"],
                 url: partial.appendingPathComponent("model.safetensors"))
        try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            .write(to: partial.appendingPathComponent("config.json"))
        for name in files where name != "config.json" && name != "model.safetensors" {
            try fm.copyItem(at: download.appendingPathComponent(name), to: partial.appendingPathComponent(name))
        }
        try? fm.removeItem(at: target)
        try fm.moveItem(at: partial, to: target)
        try fm.removeItem(at: download)
        Memory.clearCache()
    }
}
