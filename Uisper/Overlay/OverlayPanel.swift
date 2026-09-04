import AppKit
import SwiftUI

/// Borderless, non-activating panel so the target app keeps keyboard focus.
final class OverlayPanel: NSPanel {
    init<Content: View>(content: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
        // Hosting *controller*: the panel resizes to the pill, so 3 lines of text never clip.
        contentViewController = NSHostingController(rootView: content)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
