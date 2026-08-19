import AppKit
import Carbon.HIToolbox
import ServiceManagement

enum PreviewSize: Int, CaseIterable, Identifiable {
    case small, medium, large
    var id: Int { rawValue }
    var title: String { ["Small", "Medium", "Large"][rawValue] }
    var tileWidth: CGFloat { [136, 180, 240][rawValue] }
}

enum Theme: Int, CaseIterable, Identifiable {
    case system, light, dark
    var id: Int { rawValue }
    var title: String { ["System", "Light", "Dark"][rawValue] }
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .vibrantLight)
        case .dark: return NSAppearance(named: .vibrantDark)
        }
    }
}

final class Settings: ObservableObject {
    static let shared = Settings()

    private let store = UserDefaults.standard

    private func read<T>(_ key: String, _ fallback: T) -> T { store.object(forKey: key) as? T ?? fallback }
    private func write<T>(_ key: String, _ value: T) {
        store.set(value, forKey: key)
        DispatchQueue.main.async { self.objectWillChange.send() }
    }

    // MARK: General
    var enabled: Bool { get { read("enabled", true) } set { write("enabled", newValue); onEnabledChange?(newValue) } }
    var showMenuBarIcon: Bool { get { read("showMenuBarIcon", true) } set { write("showMenuBarIcon", newValue); onMenuBarIconChange?(newValue) } }
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { newValue ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
            catch { NSLog("AltTab: launch-at-login failed: \(error.localizedDescription)") }
            DispatchQueue.main.async { self.objectWillChange.send() }
        }
    }

    // MARK: Behavior
    var includeMinimized: Bool { get { read("includeMinimized", true) } set { write("includeMinimized", newValue) } }
    var includeAllSpaces: Bool { get { read("includeAllSpaces", true) } set { write("includeAllSpaces", newValue) } }
    var showTitles: Bool { get { read("showTitles", true) } set { write("showTitles", newValue) } }
    var showIcons: Bool { get { read("showIcons", true) } set { write("showIcons", newValue) } }

    // MARK: Appearance
    var previewSize: PreviewSize {
        get { PreviewSize(rawValue: read("previewSize", PreviewSize.medium.rawValue)) ?? .medium }
        set { write("previewSize", newValue.rawValue) }
    }
    var backgroundOpacity: Double { get { read("backgroundOpacity", 0.85) } set { write("backgroundOpacity", newValue) } }
    var blurEnabled: Bool { get { read("blurEnabled", true) } set { write("blurEnabled", newValue) } }
    var cornerRadius: Double { get { read("cornerRadius", 20.0) } set { write("cornerRadius", newValue) } }
    var theme: Theme {
        get { Theme(rawValue: read("theme", Theme.system.rawValue)) ?? .system }
        set { write("theme", newValue.rawValue); applyTheme() }
    }

    // MARK: Keyboard
    var nextShortcut: Shortcut {
        get { read(Shortcut.self, "nextShortcut", Shortcut(keyCode: 48, modifiers: NSEvent.ModifierFlags.option.rawValue)) }
        set { write(newValue, "nextShortcut"); onShortcutChange?() }
    }
    var previousShortcut: Shortcut {
        get { read(Shortcut.self, "previousShortcut", Shortcut(keyCode: 48, modifiers: NSEvent.ModifierFlags([.option, .shift]).rawValue)) }
        set { write(newValue, "previousShortcut"); onShortcutChange?() }
    }
    var cancelShortcut: Shortcut {
        get { read(Shortcut.self, "cancelShortcut", Shortcut(keyCode: 53, modifiers: 0)) }
        set { write(newValue, "cancelShortcut"); onShortcutChange?() }
    }

    private func read<T: Codable>(_ : T.Type, _ key: String, _ fallback: T) -> T {
        guard let data = store.data(forKey: key), let v = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
        return v
    }
    private func write<T: Codable>(_ value: T, _ key: String) {
        store.set(try? JSONEncoder().encode(value), forKey: key)
        DispatchQueue.main.async { self.objectWillChange.send() }
    }

    // MARK: Hooks (set by AppDelegate)
    var onEnabledChange: ((Bool) -> Void)?
    var onMenuBarIconChange: ((Bool) -> Void)?
    var onShortcutChange: (() -> Void)?

    func applyTheme() {
        NSApp.appearance = theme.appearance
    }

    func resetAppearance() {
        for key in ["previewSize", "backgroundOpacity", "blurEnabled", "cornerRadius", "theme"] { store.removeObject(forKey: key) }
        applyTheme()
        objectWillChange.send()
    }
}

struct Shortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt   // NSEvent.ModifierFlags raw value

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// The modifier that must stay held for the switcher to remain open.
    var holdFlag: NSEvent.ModifierFlags {
        for f in [NSEvent.ModifierFlags.option, .command, .control] where flags.contains(f) { return f }
        return []
    }

    var display: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + KeyNames.name(for: keyCode)
    }
}

enum KeyNames {
    private static let table: [UInt16: String] = [
        48: "Tab", 53: "Esc", 36: "Return", 49: "Space", 51: "Delete", 50: "`",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
    ]
    static func name(for code: UInt16) -> String {
        if let n = table[code] { return n }
        if let s = charFor(code) { return s.uppercased() }
        return "Key \(code)"
    }
    private static func charFor(_ code: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  UInt32(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
