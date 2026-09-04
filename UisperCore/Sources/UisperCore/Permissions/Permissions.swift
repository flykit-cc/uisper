import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import Speech

public enum Permission: String, CaseIterable, Sendable {
    case microphone, accessibility, inputMonitoring

    public var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .accessibility: return "Accessibility"
        case .inputMonitoring: return "Input Monitoring"
        }
    }

    public var why: String {
        switch self {
        case .microphone: return "To hear you while you hold the hotkey."
        case .accessibility: return "To place the text into the app you are using."
        case .inputMonitoring: return "To notice when you hold the hotkey."
        }
    }
}

@MainActor
public enum Permissions {
    public static func status(_ p: Permission) -> Bool {
        switch p {
        case .microphone: return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .accessibility: return AXIsProcessTrusted()
        case .inputMonitoring: return CGPreflightListenEventAccess()
        }
    }

    public static var allGranted: Bool { Permission.allCases.allSatisfy(status) }

    /// Triggers the system prompt where one exists. Returns the status afterwards.
    public static func request(_ p: Permission) async -> Bool {
        switch p {
        case .microphone:
            let ok = await AVCaptureDevice.requestAccess(for: .audio)
            // @Sendable severs the inherited @MainActor isolation: TCC calls this handler on a
            // background XPC queue, and without it the isolation check traps (SIGTRAP) at launch.
            if ok { SFSpeechRecognizer.requestAuthorization { @Sendable _ in } }   // on-device; prompt once so it never blocks later
            return ok
        case .accessibility:
            // Literal value of `kAXTrustedCheckOptionPrompt`: the SDK imports that constant
            // as a mutable global, so Swift 6 strict concurrency rejects every read of it.
            let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            return AXIsProcessTrustedWithOptions(opts)
        case .inputMonitoring:
            return CGRequestListenEventAccess()
        }
    }

    public static func openSystemSettings(_ p: Permission) {
        let pane: String
        switch p {
        case .microphone: pane = "Privacy_Microphone"
        case .accessibility: pane = "Privacy_Accessibility"
        case .inputMonitoring: pane = "Privacy_ListenEvent"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
