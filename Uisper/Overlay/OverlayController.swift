import AppKit
import SwiftUI
import UisperCore

/// Shows the pill while the session is not idle, at the bottom of the window being typed in (or the screen).
@MainActor
final class OverlayController {
    private let panel: OverlayPanel
    private let session: DictationSession

    private let anchor: () -> CGRect?

    /// `anchor` returns the frame of the window being typed in; the pill sits at its bottom edge.
    init(session: DictationSession, anchor: @escaping () -> CGRect? = { nil }) {
        self.session = session
        self.anchor = anchor
        self.panel = OverlayPanel(content: PillView(session: session))
        observe()
    }

    private func observe() {
        // Re-run whenever session.state changes (Observation tracking).
        withObservationTracking {
            _ = session.state
        } onChange: { [weak self] in
            Task { @MainActor in
                // Re-register first: tracking is one-shot, so a change between `apply` and
                // `observe` would otherwise be lost and leave the pill stale.
                self?.observe()
                self?.apply()
            }
        }
    }

    private var isIdle: Bool { if case .idle = session.state { return true }; return false }

    private func apply() {
        if case .idle = session.state { hide() } else { show() }
    }

    func show() {
        if !panel.isVisible {
            panel.layoutIfNeeded()
            let size = panel.frame.size
            var origin: NSPoint
            if let win = anchor(), let screen = NSScreen.screens.first(where: { $0.frame.intersects(win) }) {
                // Bottom-centre of the window being typed in, kept on screen.
                let v = screen.visibleFrame
                origin = NSPoint(x: win.midX - size.width / 2, y: win.minY - 8)
                origin.x = min(max(origin.x, v.minX + 8), v.maxX - size.width - 8)
                origin.y = min(max(origin.y, v.minY + 8), v.maxY - size.height - 8)
            } else {
                let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
                guard let screen else { return }
                origin = NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 96)
            }
            panel.setFrameOrigin(origin)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        // Not guarded on isVisible: a new session during the fade-out must fade back in.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel, weak self] in
            Task { @MainActor in
                // A new dictation may have re-shown the pill while it faded out.
                guard self?.isIdle ?? true else { return }
                panel.orderOut(nil)
            }
        })
    }
}
