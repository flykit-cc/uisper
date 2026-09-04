import AppKit
import SwiftUI
import UisperCore

/// Shows the pill while the session is not idle, positioned bottom-centre of the screen with the mouse.
@MainActor
final class OverlayController {
    private let panel: OverlayPanel
    private let session: DictationSession

    init(session: DictationSession) {
        self.session = session
        self.panel = OverlayPanel(content: PillView(session: session))
        observe()
    }

    private func observe() {
        // Re-run whenever session.state changes (Observation tracking).
        withObservationTracking {
            _ = session.state
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.apply()
                self?.observe()
            }
        }
    }

    private var isIdle: Bool { if case .idle = session.state { return true }; return false }

    private func apply() {
        if case .idle = session.state { hide() } else { show() }
    }

    func show() {
        if !panel.isVisible {
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            guard let screen else { return }
            panel.layoutIfNeeded()
            let size = panel.frame.size
            let origin = NSPoint(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.minY + 96
            )
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
