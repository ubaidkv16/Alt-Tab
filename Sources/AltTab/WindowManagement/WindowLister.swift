import AppKit
import ApplicationServices

/// Enumerates real application windows using the Accessibility API.
///
/// AX is used rather than CGWindowList because it is the only API that reports
/// minimized windows, windows on other Spaces, and per-window identity in a way
/// that can also be acted upon (raise / unminimize). CGWindowList is used purely
/// to seed an initial z-order.
final class WindowLister {
    static let shared = WindowLister()

    private let queue = DispatchQueue(label: "com.wobble.alttab.lister", qos: .userInitiated)
    private var lastRefresh = Date.distantPast
    private var pendingRefresh: DispatchWorkItem?

    /// Cached list, kept warm so the switcher can open instantly. Main thread only.
    private(set) var cached: [WindowInfo] = []

    private static let allowedSubroles: Set<String> = [
        kAXStandardWindowSubrole as String,
        kAXDialogSubrole as String,
    ]

    /// Refresh on a background queue and hand the result back on main.
    func refresh(_ completion: (([WindowInfo]) -> Void)? = nil) {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
                && !$0.isTerminated
                && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        let descriptors = apps.map {
            (pid: $0.processIdentifier,
             name: $0.localizedName ?? "Unknown",
             bundleID: $0.bundleIdentifier)
        }
        queue.async {
            let windows = descriptors.flatMap { Self.windows(pid: $0.pid, appName: $0.name, bundleID: $0.bundleID) }
            DispatchQueue.main.async {
                self.cached = windows
                self.lastRefresh = Date()
                IconCache.purge(keeping: Set(windows.map(\.pid)))
                completion?(windows)
            }
        }
    }

    /// Coalesced refresh, driven by focus/launch events rather than a timer.
    func scheduleRefresh() {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Refresh only if the cache is older than `maxAge`; otherwise reuse it.
    func refreshIfStale(maxAge: TimeInterval = 1.5, _ completion: @escaping ([WindowInfo]) -> Void) {
        if Date().timeIntervalSince(lastRefresh) < maxAge && !cached.isEmpty {
            completion(cached)
        } else {
            refresh(completion)
        }
    }

    private static func windows(pid: pid_t, appName: String, bundleID: String?) -> [WindowInfo] {
        let app = AXUIElement.app(pid)
        // Electron/Chromium apps only publish their AX tree once asked.
        app.set("AXManualAccessibility", kCFBooleanTrue)

        return app.elements(kAXWindowsAttribute).compactMap { win -> WindowInfo? in
            let subrole = win.str(kAXSubroleAttribute) ?? ""
            guard allowedSubroles.contains(subrole) else { return nil }

            let minimized = win.flag(kAXMinimizedAttribute)
            let frame = win.frame ?? .zero
            // Invisible helper windows.
            if !minimized && (frame.width < 40 || frame.height < 40) { return nil }
            guard let wid = win.windowID else { return nil }

            return WindowInfo(
                id: wid,
                pid: pid,
                ax: win,
                title: win.str(kAXTitleAttribute) ?? "",
                appName: appName,
                bundleID: bundleID,
                frame: frame,
                isMinimized: minimized
            )
        }
    }

    /// Front-to-back z-order of on-screen windows, used to seed the MRU list at launch.
    static func zOrderedWindowIDs() -> [CGWindowID] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let wid = info[kCGWindowNumber as String] as? CGWindowID else { return nil }
            return wid
        }
    }
}
