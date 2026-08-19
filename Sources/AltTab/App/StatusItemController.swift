import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    static let shared = StatusItemController()

    private var item: NSStatusItem?

    func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.menu = buildMenu()
            self.item = item
            refreshIcon()
            Log.debug("status item created, button window: \(item.button?.window?.frame.debugDescription ?? "none")")
        } else if !visible, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    /// The icon is slashed whenever AltTab is not actually listening, so a
    /// missing permission is visible instead of silent.
    func refreshIcon() {
        guard let button = item?.button else { return }
        let active = EventTap.shared.running
        let name = active ? "rectangle.on.rectangle.angled" : "rectangle.on.rectangle.slash"
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: "AltTab")
        button.image?.isTemplate = true
        button.toolTip = active ? "AltTab is active — press ⌥ Tab"
                                : (Permissions.accessibility ? "AltTab is turned off" : "AltTab needs Accessibility permission")
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        status.isEnabled = false
        status.tag = 2
        menu.addItem(status)
        menu.addItem(.separator())

        let enable = NSMenuItem(title: "Enable Alt+Tab", action: #selector(toggleEnabled), keyEquivalent: "")
        enable.target = self
        enable.tag = 1
        menu.addItem(enable)

        let show = NSMenuItem(title: "Show Switcher", action: #selector(showSwitcher), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        menu.addItem(.separator())

        let relaunch = NSMenuItem(title: "Relaunch AltTab", action: #selector(relaunchApp), keyEquivalent: "")
        relaunch.target = self
        relaunch.tag = 3
        menu.addItem(relaunch)

        let permissions = NSMenuItem(title: "Permissions…", action: #selector(openPermissions), keyEquivalent: "")
        permissions.target = self
        menu.addItem(permissions)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit AltTab", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.item(withTag: 1)?.state = Settings.shared.enabled ? .on : .off
        let status = menu.item(withTag: 2)
        if EventTap.shared.running {
            status?.title = "Active — press ⌥ Tab"
        } else if !Permissions.accessibility {
            status?.title = "Needs Accessibility permission"
        } else {
            status?.title = "Turned off"
        }
        if EventTap.shared.running && !Permissions.screenRecording {
            status?.title = "Active — no previews (Screen Recording off)"
        }
        menu.item(withTag: 3)?.title = Permissions.needsRelaunchForPreviews
            ? "Relaunch to Enable Previews" : "Relaunch AltTab"
        refreshIcon()
    }

    @objc private func toggleEnabled() { Settings.shared.enabled.toggle() }
    @objc private func showSwitcher() { SwitcherController.shared.cycle(backwards: false) }
    @objc private func openSettings() { SettingsWindowController.shared.show() }
    @objc private func openPermissions() { PermissionsWindowController.shared.show() }
    @objc private func relaunchApp() { Permissions.relaunch() }
    @objc private func quit() { NSApp.terminate(nil) }
}
