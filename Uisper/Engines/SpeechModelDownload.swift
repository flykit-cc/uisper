import Foundation
import Observation

/// Progress of the speech model fetch, so Settings can say what is happening instead of leaving
/// the user with a picker that appears to do nothing for several minutes.
/// Mirrors `ModelDownload` on the cleanup side; FluidAudio owns the actual download and file
/// layout, so this only mirrors what its progress handler reports.
@MainActor
@Observable
final class SpeechModelDownload {
    enum State: Equatable {
        case idle
        /// Fraction in [0, 1], and how many of the model's files have landed.
        case downloading(fraction: Double, completedFiles: Int, totalFiles: Int)
        /// CoreML is compiling the model for this Mac. No percentage, and it is not quick.
        case compiling
        case ready
        case failed(String)
    }

    private(set) var state: State = .idle

    func report(_ state: State) { self.state = state }

    /// One line for Settings, or nil when there is nothing to say.
    var notice: String? {
        switch state {
        case .idle, .ready:
            return nil
        case .downloading(let fraction, let done, let total):
            let percent = Int((fraction * 100).rounded())
            let files = total > 0 ? " (file \(done + 1) of \(total))" : ""
            return "Downloading the speech model… \(percent)%\(files). Dictation uses Apple until it is ready."
        case .compiling:
            return "Preparing the speech model for this Mac. This takes a minute and only happens once."
        case .failed(let message):
            return "Speech model download failed: \(message)"
        }
    }
}

extension SpeechModelDownload.State {
    var isFailure: Bool { if case .failed = self { return true } else { return false } }
}
