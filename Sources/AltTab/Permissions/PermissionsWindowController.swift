import AppKit
import SwiftUI

@MainActor
final class PermissionsWindowController {
    static let shared = PermissionsWindowController()

    private var window: NSWindow?
    private var timer: Timer?
    var onAccessibilityGranted: (() -> Void)?

    func showIfNeeded() {
        guard !Permissions.accessibility else { return }
        show()
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Welcome to AltTab"
            window.contentView = NSHostingView(rootView: PermissionsView())
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)

        timer?.invalidate()
        timer = Permissions.waitForAccessibility { [weak self] in
            self?.onAccessibilityGranted?()
            self?.window?.contentView?.needsDisplay = true
        }
    }

    func close() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
    }
}

struct PermissionsView: View {
    @State private var accessibility = Permissions.accessibility
    @State private var screenRecording = Permissions.screenRecording
    @State private var needsRelaunch = Permissions.needsRelaunchForPreviews
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AltTab").font(.title2.bold())
                    Text("A Windows-style window switcher for macOS").foregroundStyle(.secondary)
                }
            }

            step(
                granted: accessibility,
                title: "Accessibility",
                detail: "Accessibility permission is required so this application can detect and switch between windows.",
                action: "Open Accessibility Settings",
                required: true,
                open: {
                    Permissions.requestAccessibility()
                    Permissions.openAccessibilitySettings()
                }
            )

            step(
                granted: screenRecording,
                title: "Screen Recording (optional)",
                detail: "Screen Recording permission is what lets AltTab draw live thumbnails of your windows, the way Windows Alt+Tab does. Without it AltTab shows application icons instead.",
                action: "Open Screen Recording Settings",
                required: false,
                open: {
                    Permissions.requestScreenRecording()
                    Permissions.openScreenRecordingSettings()
                }
            )

            Spacer()

            if needsRelaunch {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(.tint)
                    Text("Screen Recording is granted. Relaunch AltTab to start showing window previews.")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Relaunch", action: Permissions.relaunch).keyboardShortcut(.defaultAction)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.15)))
            } else {
                Text("After granting Accessibility, AltTab starts listening immediately — press ⌥ Tab to try it. If macOS does not pick up the change, quit and relaunch AltTab.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .frame(width: 480, height: 400, alignment: .topLeading)
        .onReceive(poll) { _ in
            accessibility = Permissions.accessibility
            screenRecording = Permissions.screenRecording
            needsRelaunch = Permissions.needsRelaunchForPreviews
        }
    }

    private func step(granted: Bool, title: String, detail: String, action: String, required: Bool, open: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: granted ? "checkmark.circle.fill" : (required ? "exclamationmark.circle.fill" : "circle"))
                    .foregroundStyle(granted ? Color.green : (required ? Color.orange : Color.secondary))
                Text(title).font(.headline)
            }
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !granted { Button(action, action: open) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}
