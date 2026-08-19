import AppKit
import ApplicationServices

struct WindowInfo: Identifiable, Equatable {
    let id: CGWindowID          // stable window server id
    let pid: pid_t
    let ax: AXUIElement
    let title: String
    let appName: String
    let bundleID: String?
    let frame: CGRect
    let isMinimized: Bool

    var icon: NSImage? { IconCache.icon(pid: pid) }
    var displayTitle: String { title.isEmpty ? appName : title }

    static func == (a: WindowInfo, b: WindowInfo) -> Bool { a.id == b.id }
}


/// Application icons are looked up per rendered tile; cache them per pid.
enum IconCache {
    private static var cache: [pid_t: NSImage] = [:]

    static func icon(pid: pid_t) -> NSImage? {
        if let hit = cache[pid] { return hit }
        guard let icon = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
        cache[pid] = icon
        return icon
    }

    static func purge(keeping pids: Set<pid_t>) {
        cache = cache.filter { pids.contains($0.key) }
    }
}
