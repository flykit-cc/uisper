import AppKit

/// Saves and restores the pasteboard around a synthetic paste.
/// ponytail: saves the plain string only; add per-type item copies if users report lost rich clipboard content.
public struct PasteboardSnapshot: Sendable {
    private let string: String?

    public static func take(_ pb: NSPasteboard) -> PasteboardSnapshot {
        PasteboardSnapshot(string: pb.string(forType: .string))
    }

    public func restore(to pb: NSPasteboard) {
        pb.clearContents()
        if let string { pb.setString(string, forType: .string) }
    }
}
