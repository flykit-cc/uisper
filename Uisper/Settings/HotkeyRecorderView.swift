import AppKit
import SwiftUI
import UisperCore

/// A click-then-press shortcut field. Click it, press any combination, and that becomes the
/// hotkey. Esc cancels, ⌫ resets to ⌥ Space.
struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var hotkey: Hotkey
    let onRecordingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        configure(view)
        return view
    }

    func updateNSView(_ view: HotkeyRecorderNSView, context: Context) {
        configure(view)
    }

    private func configure(_ view: HotkeyRecorderNSView) {
        view.hotkey = hotkey
        view.onChange = { hotkey = $0 }
        view.onRecordingChanged = onRecordingChanged
    }
}

final class HotkeyRecorderNSView: NSView {
    var hotkey: Hotkey = .optionSpace { didSet { needsDisplay = true } }
    var onChange: ((Hotkey) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?

    private var recording = false { didSet { needsDisplay = true } }
    /// The modifier set seen on the previous flagsChanged, so releasing them all can be
    /// recorded as a modifier-only chord.
    private var lastModifiers: CGEventFlags = []
    private var sawKeyDown = false

    private static let escape: UInt16 = 53
    private static let delete: UInt16 = 51

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 160, height: 24) }

    override func draw(_ dirtyRect: NSRect) {
        let frame = bounds.insetBy(dx: 1.5, dy: 1.5)
        let path = NSBezierPath(roundedRect: frame, xRadius: 5, yRadius: 5)
        NSColor.textBackgroundColor.setFill()
        path.fill()
        path.lineWidth = recording ? 2 : 1
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()

        let text = recording ? "Type shortcut…" : hotkey.displayString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: recording ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let origin = NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        beginRecording()
    }

    override func resignFirstResponder() -> Bool {
        endRecording()
        return true
    }

    /// Switching away mid-recording would otherwise leave the global hotkey suspended.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let center = NotificationCenter.default
        center.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        guard let window else { return }
        center.addObserver(self, selector: #selector(windowResignedKey), name: NSWindow.didResignKeyNotification, object: window)
    }

    @objc private func windowResignedKey() { endRecording() }

    /// ⌘ chords arrive as key equivalents, never as keyDown, so route them in while recording.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        sawKeyDown = true
        switch event.keyCode {
        case Self.escape:
            endRecording()
        case Self.delete:
            apply(.optionSpace)
        default:
            apply(Hotkey(keyCode: Int64(event.keyCode), flags: Self.flags(event.modifierFlags)))
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard recording else { return super.flagsChanged(with: event) }
        let now = Self.flags(event.modifierFlags)
        defer { lastModifiers = now }
        guard now.isEmpty, !lastModifiers.isEmpty, !sawKeyDown else { return }
        apply(Hotkey(keyCode: nil, flags: lastModifiers))
    }

    private func apply(_ new: Hotkey) {
        hotkey = new
        onChange?(new)
        endRecording()
    }

    private func beginRecording() {
        guard !recording else { return }
        lastModifiers = []
        sawKeyDown = false
        recording = true
        onRecordingChanged?(true)
    }

    private func endRecording() {
        guard recording else { return }
        recording = false
        onRecordingChanged?(false)
    }

    /// NSEvent and CGEvent modifier raw values differ, so convert explicitly.
    private static func flags(_ modifiers: NSEvent.ModifierFlags) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }
}
