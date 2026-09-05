import AppKit
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
    public var hotkey: Hotkey { didSet { decoder = HotkeyDecoder(hotkey: hotkey) } }
    private var decoder: HotkeyDecoder
    private let onEvent: @MainActor (HotkeyEvent) -> Void
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// While set, the decoder is bypassed (no dictation) and every key press, including
    /// F14/F15 brightness events, is reported here and swallowed. Used by the recorder field.
    public var recordingSink: (@MainActor (_ type: CGEventType, _ keyCode: Int64, _ flags: CGEventFlags) -> Bool)?
    private let log = Logger(subsystem: "cc.flykit.uisper", category: "hotkey")

    public init(hotkey: Hotkey, onEvent: @escaping @MainActor (HotkeyEvent) -> Void) {
        self.hotkey = hotkey
        self.decoder = HotkeyDecoder(hotkey: hotkey)
        self.onEvent = onEvent
    }

    public func start() throws {
        guard tap == nil else { return }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << Self.systemDefined.rawValue)
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

    /// NX_SYSDEFINED: macOS delivers F14/F15 (brightness) and other media keys this way, not as keyDown.
    static let systemDefined = CGEventType(rawValue: 14)!

    /// Maps a brightness system event to (virtual key code, isDown); nil for anything else.
    public static func brightnessKey(subtype: Int, data1: Int) -> (keyCode: Int64, isDown: Bool)? {
        guard subtype == 8 else { return nil }
        let key = (data1 >> 16) & 0xFFFF
        let isDown = ((data1 >> 8) & 0xFF) == 0x0A
        switch key {
        case 2: return (113, isDown)   // NX_KEYTYPE_BRIGHTNESS_UP   → F15
        case 3: return (107, isDown)   // NX_KEYTYPE_BRIGHTNESS_DOWN → F14
        default: return nil
        }
    }

    /// Returns true when the event must be swallowed (not forwarded to the focused app).
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            log.warning("event tap re-enabled after \(type.rawValue)")
            return false
        }
        var type = type
        var keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == Self.systemDefined {
            guard let ns = NSEvent(cgEvent: event),
                  let key = Self.brightnessKey(subtype: Int(ns.subtype.rawValue), data1: ns.data1) else { return false }
            type = key.isDown ? .keyDown : .keyUp
            keyCode = key.keyCode
        }
        if let recordingSink {
            // Recorder field is open: keys go to it instead of the decoder; no dictation.
            return recordingSink(type, keyCode, event.flags.intersection(Hotkey.modifierMask))
        }
        let result = decoder.handle(type: type, keyCode: keyCode, flags: event.flags)
        if let e = result.event { onEvent(e) }
        return result.swallow
    }
}
