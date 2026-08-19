import AppKit
import SwiftUI

extension Settings {
    func binding<T>(_ keyPath: ReferenceWritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(get: { self[keyPath: keyPath] }, set: { self[keyPath: keyPath] = $0 })
    }
}

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            behavior.tabItem { Label("Behavior", systemImage: "slider.horizontal.3") }
            appearance.tabItem { Label("Appearance", systemImage: "paintbrush") }
            keyboard.tabItem { Label("Keyboard", systemImage: "keyboard") }
        }
        .frame(width: 460, height: 340)
    }

    private var general: some View {
        Form {
            Toggle("Enable Alt+Tab", isOn: settings.binding(\.enabled))
            Toggle("Launch at Login", isOn: settings.binding(\.launchAtLogin))
            Toggle("Show menu-bar icon", isOn: settings.binding(\.showMenuBarIcon))

            Divider().padding(.vertical, 4)

            LabeledContent("Accessibility") { permissionRow(Permissions.accessibility, open: Permissions.openAccessibilitySettings) }
            LabeledContent("Screen Recording") { permissionRow(Permissions.screenRecording, open: Permissions.openScreenRecordingSettings) }
            Text("Screen Recording is optional — without it, application icons are shown instead of window previews.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func permissionRow(_ granted: Bool, open: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? Color.green : Color.orange)
            Text(granted ? "Granted" : "Not granted")
            if !granted { Button("Open Settings…", action: open) }
        }
    }

    private var behavior: some View {
        Form {
            Toggle("Include minimized windows", isOn: settings.binding(\.includeMinimized))
            Toggle("Include windows from all Spaces", isOn: settings.binding(\.includeAllSpaces))
            Toggle("Show window titles", isOn: settings.binding(\.showTitles))
            Toggle("Show application icons", isOn: settings.binding(\.showIcons))
        }
        .formStyle(.grouped)
    }

    private var appearance: some View {
        Form {
            Picker("Preview size", selection: settings.binding(\.previewSize)) {
                ForEach(PreviewSize.allCases) { Text($0.title).tag($0) }
            }
            Picker("Theme", selection: settings.binding(\.theme)) {
                ForEach(Theme.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Background blur", isOn: settings.binding(\.blurEnabled))
            VStack(alignment: .leading) {
                Text("Background opacity  \(Int(settings.backgroundOpacity * 100))%")
                Slider(value: settings.binding(\.backgroundOpacity), in: 0.3...1.0)
            }
            VStack(alignment: .leading) {
                Text("Corner radius  \(Int(settings.cornerRadius))pt")
                Slider(value: settings.binding(\.cornerRadius), in: 0...32)
            }
            Button("Reset Appearance") { settings.resetAppearance() }
        }
        .formStyle(.grouped)
    }

    private var keyboard: some View {
        Form {
            ShortcutRecorder(title: "Next window", shortcut: settings.binding(\.nextShortcut))
            ShortcutRecorder(title: "Previous window", shortcut: settings.binding(\.previousShortcut))
            ShortcutRecorder(title: "Cancel", shortcut: settings.binding(\.cancelShortcut))
            Text("The switcher stays open while the modifier of the “Next window” shortcut is held, and activates the selection when it is released.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

struct ShortcutRecorder: View {
    let title: String
    @Binding var shortcut: Shortcut
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        LabeledContent(title) {
            Button(recording ? "Press keys…" : shortcut.display) { recording ? stop() : start() }
                .frame(minWidth: 110)
                .onDisappear(perform: stop)
        }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
            shortcut = Shortcut(keyCode: event.keyCode, modifiers: event.modifierFlags.intersection(relevant).rawValue)
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
