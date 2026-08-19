import AppKit
import ApplicationServices

enum Permissions {
    /// Accessibility — required to read window lists and to activate windows.
    static var accessibility: Bool { AXIsProcessTrusted() }

    /// Screen Recording — required only for window thumbnails. The switcher
    /// still works without it, showing application icons instead of previews.
    static var screenRecording: Bool { CGPreflightScreenCaptureAccess() }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Presents the system prompt and, more importantly, registers AltTab in the
    /// Screen Recording list so there is something for the user to switch on.
    /// Blocking, so never call it on the main thread.
    static func requestScreenRecording() {
        DispatchQueue.global(qos: .userInitiated).async { _ = CGRequestScreenCaptureAccess() }
    }

    private static let askedKey = "askedForScreenRecording"
    static var hasAskedForScreenRecording: Bool {
        get { UserDefaults.standard.bool(forKey: askedKey) }
        set { UserDefaults.standard.set(newValue, forKey: askedKey) }
    }

    /// macOS only hands a process its Screen Recording grant at start-up, so a
    /// grant made while AltTab is running needs a restart before captures work.
    static let hadScreenRecordingAtLaunch = CGPreflightScreenCaptureAccess()
    static var needsRelaunchForPreviews: Bool { !hadScreenRecordingAtLaunch && screenRecording }

    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private static func open(_ url: String) {
        guard let u = URL(string: url) else { return }
        NSWorkspace.shared.open(u)
    }

    /// Polls until accessibility is granted. Only runs while the setup window is
    /// open, so it costs nothing in normal operation.
    static func waitForAccessibility(_ granted: @escaping () -> Void) -> Timer {
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
            if AXIsProcessTrusted() {
                t.invalidate()
                granted()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
