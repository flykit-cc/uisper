import CoreGraphics
import Foundation
import os

public enum HotkeyError: Error, LocalizedError {
    case inputMonitoringDenied
    public var errorDescription: String? { "Input Monitoring permission is required for the hotkey." }
}

/// Session-level CGEvent tap that feeds a HotkeyDecoder and reports hotkey events on the main actor.
@MainActor
public final class HotkeyMonitor {
    public var choice: HotkeyChoice { didSet { decoder = HotkeyDecoder(choice: choice) } }
    private var decoder: HotkeyDecoder
    private let onEvent: @MainActor (HotkeyEvent) -> Void
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let log = Logger(subsystem: "cc.flykit.uisper", category: "hotkey")

    public init(choice: HotkeyChoice, onEvent: @escaping @MainActor (HotkeyEvent) -> Void) {
        self.choice = choice
        self.decoder = HotkeyDecoder(choice: choice)
        self.onEvent = onEvent
    }

    public func start() throws {
        guard tap == nil else { return }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                let swallow = MainActor.assumeIsolated { monitor.handle(type: type, event: event) }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
            throw HotkeyError.inputMonitoringDenied
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        log.info("event tap started")
    }

    public func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    /// Returns true when the event must be swallowed (not forwarded to the focused app).
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            log.warning("event tap re-enabled after \(type.rawValue)")
            return false
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let result = decoder.handle(type: type, keyCode: keyCode, flags: event.flags)
        if let e = result.event { onEvent(e) }
        return result.swallow
    }
}
