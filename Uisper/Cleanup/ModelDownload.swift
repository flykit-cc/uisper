import Foundation
import Observation
import os

/// Fetches a model into Application Support on first use, so the app download stays small
/// (GitHub Releases caps files at 2 GB and the cleanup model alone is 2.1 GB).
@MainActor
@Observable
final class ModelDownload {
    enum State: Equatable { case missing, downloading(Double), converting, ready, failed(String) }

    struct Source: Sendable {
        let baseURL: URL
        let files: [String]
        let sizeLabel: String

        nonisolated func isComplete(in directory: URL) -> Bool {
            files.allSatisfy { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
        }
    }

    // ponytail: served straight from Hugging Face's CDN. Move to R2 by changing this one URL.
    nonisolated static let qwen = Source(
        baseURL: URL(string: "https://huggingface.co/mlx-community/Qwen3-4B-4bit/resolve/main/")!,
        files: ["config.json", "model.safetensors", "model.safetensors.index.json", "tokenizer.json",
                "tokenizer_config.json", "special_tokens_map.json", "added_tokens.json", "merges.txt", "vocab.json"],
        sizeLabel: "2.1 GB")

    let source: Source
    /// Where the files land.
    let directory: URL
    private(set) var state: State
    private let isReady: @Sendable () -> Bool
    private let convert: (@Sendable () async throws -> Void)?
    private var task: Task<Void, Error>?
    private let log = Logger(subsystem: "cc.flykit.uisper", category: "model-download")

    /// `convert` is for a model published in a form uisper cannot load: it runs once every file is in
    /// `directory` and writes the copy `isReady` looks for.
    init(_ source: Source = qwen, directory: URL = defaultDirectory(),
         isReady: (@Sendable () -> Bool)? = nil, convert: (@Sendable () async throws -> Void)? = nil) {
        self.source = source
        self.directory = directory
        self.isReady = isReady ?? { source.isComplete(in: directory) }
        self.convert = convert
        state = self.isReady() ? .ready : .missing
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("uisper/Models/Qwen3-4B-4bit", isDirectory: true)
    }

    /// Returns when the model is on disk. Starts the download if needed; concurrent callers share it.
    func ensure() async throws {
        if state == .ready { return }
        if let task { return try await task.value }
        let task = Task { try await download() }
        self.task = task
        defer { self.task = nil }
        try await task.value
    }

    private func download() async throws {
        state = .downloading(0)
        do {
            if !isReady() {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                for name in source.files {
                    let target = directory.appendingPathComponent(name)
                    if FileManager.default.fileExists(atPath: target.path) { continue }
                    try await fetch(name, to: target)
                }
                if let convert {
                    state = .converting
                    try await Task.detached(priority: .utility) { try await convert() }.value
                }
            }
            state = .ready
            log.info("model ready from \(self.directory.path, privacy: .public)")
        } catch {
            state = .failed(error.localizedDescription)
            log.error("model download failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func fetch(_ name: String, to target: URL) async throws {
        // Only the weights file is big enough to be worth a progress bar.
        let reporter = name == "model.safetensors" ? ProgressReporter { [weak self] fraction in
            Task { @MainActor in self?.state = .downloading(fraction) }
        } : nil
        let (tmp, response) = try await URLSession.shared.download(from: source.baseURL.appendingPathComponent(name), delegate: reporter)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Server refused \(name)."])
        }
        // `tmp` is deleted when this call returns, so move it now.
        _ = try FileManager.default.replaceItemAt(target, withItemAt: tmp)
    }
}

/// Forwards download progress in whole percents.
private final class ProgressReporter: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private var lastPercent = -1

    init(onProgress: @escaping @Sendable (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let percent = Int(totalBytesWritten * 100 / max(totalBytesExpectedToWrite, 1))
        guard percent != lastPercent else { return }
        lastPercent = percent
        onProgress(Double(percent) / 100)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
