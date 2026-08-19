import AppKit
import SwiftUI

/// `AltTab --self-test [outputDirectory]`
///
/// Headless verification of everything that does not need Accessibility or
/// Screen Recording: grid geometry, MRU ordering, shortcut parsing, and an
/// offscreen render of the real switcher overlay to a PNG.
@MainActor
enum SelfTest {
    private static var failures = 0

    static func run(outputDirectory: String) -> Never {
        layout()
        mru()
        shortcuts()
        render(into: outputDirectory)
        live()

        print(failures == 0 ? "\nAll self-tests passed." : "\n\(failures) self-test failure(s).")
        exit(failures == 0 ? 0 : 1)
    }

    private static func check(_ condition: Bool, _ message: String) {
        print("\(condition ? "  ok  " : " FAIL ") \(message)")
        if !condition { failures += 1 }
    }

    // MARK: - Geometry

    private static func layout() {
        print("Layout")
        let one = SwitcherLayout(count: 1, tileWidth: 180, showTitles: true, maxWidth: 1400, maxHeight: 800)
        check(one.columns == 1 && one.rows == 1, "single window is a 1x1 grid")
        check(one.panelSize.width == SwitcherLayout.padding * 2 + 180, "panel hugs its content")

        let row = SwitcherLayout(count: 5, tileWidth: 180, showTitles: true, maxWidth: 1400, maxHeight: 800)
        check(row.columns == 5 && row.rows == 1, "five windows fit on one row at 1400pt")

        let wrapped = SwitcherLayout(count: 20, tileWidth: 180, showTitles: true, maxWidth: 1400, maxHeight: 800)
        check(wrapped.columns * wrapped.rows >= 20, "twenty windows wrap onto enough cells")
        check(wrapped.panelSize.width <= 1400, "wrapped panel never exceeds the display")

        let narrow = SwitcherLayout(count: 8, tileWidth: 240, showTitles: false, maxWidth: 500, maxHeight: 400)
        check(narrow.columns >= 1 && narrow.panelSize.width <= 500, "narrow display still yields a valid grid")
        check(narrow.panelSize.height <= 400, "panel height is clamped to the display")

        let titled = SwitcherLayout(count: 3, tileWidth: 180, showTitles: true, maxWidth: 1400, maxHeight: 800)
        let untitled = SwitcherLayout(count: 3, tileWidth: 180, showTitles: false, maxWidth: 1400, maxHeight: 800)
        check(titled.tile.height > untitled.tile.height, "hiding titles shortens the tile")
    }

    // MARK: - MRU

    private static func mru() {
        print("MRU")
        let windows = (1...4).map { synthetic(id: CGWindowID($0), app: "App\($0)", title: "Window \($0)") }
        let tracker = MRUTracker.shared
        for id in [1, 2, 3, 4] as [CGWindowID] { tracker.bump(id) }   // 4 is now most recent
        var order = tracker.sorted(windows).map(\.id)
        check(order == [4, 3, 2, 1], "most recently used comes first (got \(order))")

        // Chrome -> VS Code -> Terminal -> Chrome: next Alt+Tab must offer Terminal.
        tracker.bump(1); tracker.bump(2); tracker.bump(3); tracker.bump(1)
        order = tracker.sorted(windows).map(\.id)
        check(order.first == 1, "current window is index 0")
        check(order.count > 1 && order[1] == 3, "index 1 is the previously used window (got \(order))")

        let unseen = synthetic(id: 999, app: "New", title: "Fresh")
        check(tracker.sorted(windows + [unseen]).last?.id == 999, "never-seen windows sort last")
    }

    // MARK: - Shortcuts

    private static func shortcuts() {
        print("Shortcuts")
        let next = Shortcut(keyCode: 48, modifiers: NSEvent.ModifierFlags.option.rawValue)
        let previous = Shortcut(keyCode: 48, modifiers: NSEvent.ModifierFlags([.option, .shift]).rawValue)
        check(next.display == "⌥Tab", "next shortcut renders as ⌥Tab (got \(next.display))")
        check(previous.display == "⌥⇧Tab", "previous shortcut renders as ⌥⇧Tab (got \(previous.display))")
        check(next.holdFlag == .option, "the held modifier is Option")
        check(Shortcut(keyCode: 53, modifiers: 0).display == "Esc", "cancel renders as Esc")

        let roundTrip = try? JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(previous))
        check(roundTrip == previous, "shortcuts survive a defaults round-trip")
    }

    // MARK: - Offscreen render

    private static func render(into directory: String) {
        print("Render")
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .prefix(6)
        var windows: [WindowInfo] = []
        for (index, app) in apps.enumerated() {
            windows.append(WindowInfo(
                id: CGWindowID(5000 + index),
                pid: app.processIdentifier,
                ax: AXUIElementCreateApplication(app.processIdentifier),
                title: "\(app.localizedName ?? "App") — sample window \(index + 1)",
                appName: app.localizedName ?? "App",
                bundleID: app.bundleIdentifier,
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                isMinimized: index == 3
            ))
        }
        while windows.count < 6 {
            windows.append(synthetic(id: CGWindowID(6000 + windows.count), app: "Sample", title: "Sample window"))
        }
        for window in windows where !window.isMinimized {
            PreviewCache.shared.store(gradient(seed: Int(window.id)), for: window.id)
        }

        let model = SwitcherModel()
        model.windows = windows
        model.selected = 1
        model.layout = SwitcherLayout(count: windows.count, tileWidth: Settings.shared.previewSize.tileWidth,
                                      showTitles: true, maxWidth: 1200, maxHeight: 800)
        check(model.layout.panelSize.width > 0 && model.layout.panelSize.height > 0, "overlay has a positive size")

        // NSVisualEffectView cannot rasterise offscreen; render the solid variant.
        let blur = Settings.shared.blurEnabled
        Settings.shared.blurEnabled = false
        defer { Settings.shared.blurEnabled = blur }

        let view = SwitcherView(model: model, onPick: { _ in }, onHover: { _ in })
        let renderer = ImageRenderer(content: view.frame(width: model.layout.panelSize.width,
                                                         height: model.layout.panelSize.height))
        renderer.scale = 2

        guard let cgImage = renderer.cgImage else {
            check(false, "overlay rendered offscreen")
            return
        }
        check(cgImage.width == Int(model.layout.panelSize.width * 2), "render is Retina (2x backing)")

        let url = URL(fileURLWithPath: directory).appendingPathComponent("switcher-preview.png")
        let rep = NSBitmapImageRep(cgImage: cgImage)
        if let data = rep.representation(using: .png, properties: [:]), (try? data.write(to: url)) != nil {
            check(true, "wrote \(url.path)")
        } else {
            check(false, "wrote \(url.path)")
        }
    }

    // MARK: - Live system checks
    //
    // These need real permissions. Run this from the installed bundle so macOS
    // recognises the same code identity you granted access to:
    //   /Applications/AltTab.app/Contents/MacOS/AltTab --self-test

    private static func live() {
        print("System")
        let ax = Permissions.accessibility
        print("       Accessibility: \(ax ? "granted" : "NOT GRANTED")")
        print("       Screen Recording: \(Permissions.screenRecording ? "granted" : "not granted (icons will be used)")")

        guard ax else {
            print("       Skipping live window checks — grant Accessibility and run again.")
            return
        }

        let done = DispatchSemaphore(value: 0)
        var windows: [WindowInfo] = []
        WindowLister.shared.refresh { windows = $0; done.signal() }
        while done.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        check(!windows.isEmpty, "enumerated \(windows.count) window(s)")

        let byApp = Dictionary(grouping: windows, by: \.appName)
        let multi = byApp.filter { $0.value.count > 1 }
        print("       Apps with several windows: \(multi.isEmpty ? "none open" : multi.map { "\($0.key) x\($0.value.count)" }.joined(separator: ", "))")
        check(windows.count == Set(windows.map(\.id)).count, "every window has a distinct id")
        check(!windows.contains { $0.appName == "Dock" || $0.appName == "Window Server" }, "system UI is filtered out")
        print("       Minimized windows found: \(windows.filter(\.isMinimized).count)")

        for window in windows.prefix(8) {
            print("       - \(window.appName): \(window.displayTitle)\(window.isMinimized ? "  [minimized]" : "")")
        }

        check(NSScreen.screens.count >= 1, "\(NSScreen.screens.count) display(s) detected")

        guard Permissions.screenRecording, let first = windows.first(where: { !$0.isMinimized }) else { return }
        PreviewCache.shared.warm([first], targetWidth: 240, scale: 2)
        let deadline = Date().addingTimeInterval(4)
        while PreviewCache.shared.image(for: first.id) == nil && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        check(PreviewCache.shared.image(for: first.id) != nil, "captured a live thumbnail of “\(first.displayTitle)”")
    }

    // MARK: - Helpers

    private static func synthetic(id: CGWindowID, app: String, title: String) -> WindowInfo {
        WindowInfo(id: id, pid: ProcessInfo.processInfo.processIdentifier,
                   ax: AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier),
                   title: title, appName: app, bundleID: nil,
                   frame: CGRect(x: 0, y: 0, width: 1200, height: 800), isMinimized: false)
    }

    private static func gradient(seed: Int) -> CGImage {
        let size = 320
        let context = CGContext(data: nil, width: size, height: size * 2 / 3, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let hue = CGFloat(seed % 7) / 7.0
        let colors = [NSColor(hue: hue, saturation: 0.55, brightness: 0.95, alpha: 1).cgColor,
                      NSColor(hue: hue, saturation: 0.75, brightness: 0.45, alpha: 1).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: .zero,
                                   end: CGPoint(x: context.width, y: context.height), options: [])
        return context.makeImage()!
    }
}
