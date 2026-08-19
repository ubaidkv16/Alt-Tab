import AppKit
import SwiftUI

@MainActor
final class SwitcherController {
    static let shared = SwitcherController()

    private let model = SwitcherModel()
    private lazy var panel: SwitcherPanel = makePanel()
    private(set) var isOpen = false

    private func makePanel() -> SwitcherPanel {
        let panel = SwitcherPanel()
        let view = SwitcherView(
            model: model,
            onPick: { [weak self] index in
                self?.model.selected = index
                self?.commit()
            },
            onHover: { [weak self] index in
                self?.model.selected = index
            }
        )
        panel.contentView = NSHostingView(rootView: view)
        return panel
    }

    // MARK: - Commands

    func cycle(backwards: Bool) {
        guard Settings.shared.enabled else { return }
        Log.debug("cycle backwards=\(backwards) open=\(isOpen)")
        if isOpen {
            let count = model.windows.count
            guard count > 0 else { return }
            model.selected = (model.selected + (backwards ? -1 : 1) + count) % count
        } else {
            open(startBackwards: backwards)
        }
    }

    func navigate(_ direction: NavDirection) {
        guard isOpen, !model.windows.isEmpty else { return }
        let count = model.windows.count
        let columns = max(1, model.layout.columns)
        let step: Int
        switch direction {
        case .left: step = -1
        case .right: step = 1
        case .up: step = -columns
        case .down: step = columns
        }
        model.selected = min(max(model.selected + step, 0), count - 1)
        Log.debug("navigate \(direction) -> \(model.selected)")
    }

    func commit() {
        if opening && !isOpen { pendingCommit = true; return }
        guard isOpen else { return }
        let window = model.windows.indices.contains(model.selected) ? model.windows[model.selected] : nil
        Log.debug("commit -> \(window.map { "\($0.appName): \($0.displayTitle)" } ?? "nothing")")
        close()
        if let window { WindowActivator.activate(window) }
    }

    func cancel() {
        if opening && !isOpen { opening = false; pendingCommit = false; return }
        guard isOpen else { return }
        Log.debug("cancel")
        close()
    }

    // MARK: - Presentation

    private var opening = false
    private var pendingCommit = false

    private func open(startBackwards: Bool) {
        guard !opening else { return }
        opening = true
        let show: ([WindowInfo]) -> Void = { [weak self] raw in
            guard let self else { return }
            guard self.opening else { return }
            self.opening = false
            let windows = MRUTracker.shared.sorted(self.filter(raw))
            guard !windows.isEmpty else { self.pendingCommit = false; return }

            self.model.windows = windows
            self.model.selected = startBackwards ? windows.count - 1 : min(1, windows.count - 1)

            // Quick tap: the modifier was released before the list was ready.
            if self.pendingCommit {
                self.pendingCommit = false
                Log.debug("quick tap -> \(windows[self.model.selected].appName)")
                WindowActivator.activate(windows[self.model.selected])
                return
            }
            self.present()
        }

        // Warm cache => instant. Cold cache (first press only) => one AX pass.
        if !WindowLister.shared.cached.isEmpty {
            show(WindowLister.shared.cached)
            WindowLister.shared.refresh { [weak self] fresh in
                guard let self, self.isOpen else { return }
                self.update(with: fresh)
            }
        } else {
            WindowLister.shared.refresh(show)
        }
    }

    private func filter(_ windows: [WindowInfo]) -> [WindowInfo] {
        let settings = Settings.shared
        var result = windows
        if !settings.includeMinimized { result = result.filter { !$0.isMinimized } }
        if !settings.includeAllSpaces {
            let onCurrentSpace = Set(WindowLister.zOrderedWindowIDs())
            result = result.filter { onCurrentSpace.contains($0.id) || $0.isMinimized }
        }
        return result
    }

    /// Refreshed list arrives while the switcher is up: keep the same selected window.
    private func update(with raw: [WindowInfo]) {
        let windows = MRUTracker.shared.sorted(filter(raw))
        guard !windows.isEmpty else { return }
        let selectedID = model.windows.indices.contains(model.selected) ? model.windows[model.selected].id : nil
        model.windows = windows
        model.selected = selectedID.flatMap { id in windows.firstIndex { $0.id == id } } ?? min(model.selected, windows.count - 1)
        layoutAndPosition()
        PreviewCache.shared.forget(idsNotIn: Set(windows.map(\.id)))
        warmPreviews()
    }

    private func present() {
        layoutAndPosition()
        isOpen = true
        EventTap.shared.switcherOpen = true

        Log.debug("present \(model.windows.count) windows, selected=\(model.selected) frame=\(panel.frame)")
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        warmPreviews()
    }

    private func warmPreviews() {
        let scale = panel.screen?.backingScaleFactor ?? 2
        PreviewCache.shared.warm(model.windows, targetWidth: model.layout.tile.width, scale: scale)
    }

    private func close() {
        opening = false
        pendingCommit = false
        isOpen = false
        EventTap.shared.switcherOpen = false
        panel.orderOut(nil)
    }

    private func layoutAndPosition() {
        let screen = targetScreen()
        let visible = screen.visibleFrame
        let layout = SwitcherLayout(
            count: model.windows.count,
            tileWidth: Settings.shared.previewSize.tileWidth,
            showTitles: Settings.shared.showTitles,
            maxWidth: visible.width * 0.92,
            maxHeight: visible.height * 0.85
        )
        model.layout = layout

        let origin = NSPoint(
            x: visible.midX - layout.panelSize.width / 2,
            y: visible.midY - layout.panelSize.height / 2
        )
        panel.setFrame(NSRect(origin: origin, size: layout.panelSize), display: true)
    }

    /// The display holding the currently active window, falling back to the
    /// display under the pointer, then the main display.
    private func targetScreen() -> NSScreen {
        if let front = model.windows.first, front.frame != .zero {
            let center = CGPoint(x: front.frame.midX, y: front.frame.midY)
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(Self.cocoaPoint(center)) }) {
                return screen
            }
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// Accessibility reports top-left origin global coordinates; AppKit uses
    /// bottom-left relative to the primary display.
    private static func cocoaPoint(_ point: CGPoint) -> CGPoint {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        return CGPoint(x: point.x, y: primaryTop - point.y)
    }
}
