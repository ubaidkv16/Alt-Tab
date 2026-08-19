import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = Permissions.hadScreenRecordingAtLaunch   // snapshot before anything grants it
        let settings = Settings.shared
        settings.applyTheme()

        settings.onEnabledChange = { [weak self] enabled in
            enabled ? self?.startTap() : EventTap.shared.stop()
            StatusItemController.shared.refreshIcon()
        }
        settings.onMenuBarIconChange = { StatusItemController.shared.setVisible($0) }
        settings.onShortcutChange = { EventTap.shared.reloadShortcuts() }

        StatusItemController.shared.setVisible(settings.showMenuBarIcon)

        let tap = EventTap.shared
        tap.onCycle = { SwitcherController.shared.cycle(backwards: $0) }
        tap.onCommit = { SwitcherController.shared.commit() }
        tap.onCancel = { SwitcherController.shared.cancel() }
        tap.onNavigate = { SwitcherController.shared.navigate($0) }

        PermissionsWindowController.shared.onAccessibilityGranted = { [weak self] in
            self?.begin()
            // Only dismiss setup once previews are sorted too, otherwise the
            // Screen Recording step would vanish before it was ever shown.
            if Permissions.screenRecording { PermissionsWindowController.shared.close() }
        }

        if Permissions.accessibility {
            begin()
        } else {
            // Ask the system directly: this is what puts AltTab into the
            // Accessibility list, so the user has something to switch on.
            Permissions.requestAccessibility()
            PermissionsWindowController.shared.showIfNeeded()
        }
        StatusItemController.shared.refreshIcon()
    }

    private func begin() {
        FocusTracker.shared.start()
        WindowLister.shared.refresh()
        if Settings.shared.enabled { startTap() }
        requestPreviewsIfNeeded()
    }

    /// Thumbnails are the whole point of the overlay, so ask for Screen Recording
    /// as soon as we are able to — but only once, so a deliberate "no" is respected.
    private func requestPreviewsIfNeeded() {
        guard !Permissions.screenRecording else { return }
        guard !Permissions.hasAskedForScreenRecording else { return }
        Permissions.hasAskedForScreenRecording = true
        Permissions.requestScreenRecording()
        PermissionsWindowController.shared.show()
    }

    private func startTap() {
        guard Permissions.accessibility else {
            PermissionsWindowController.shared.show()
            return
        }
        EventTap.shared.reloadShortcuts()
        if EventTap.shared.start() {
            Log.debug("event tap running")
        } else {
            NSLog("AltTab: could not create the event tap")
        }
        StatusItemController.shared.refreshIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        EventTap.shared.stop()
    }
}
