import AppKit

/// Most-recently-used ordering of windows, newest first.
final class MRUTracker {
    static let shared = MRUTracker()

    private(set) var order: [CGWindowID] = []

    func seed() {
        order = WindowLister.zOrderedWindowIDs()
    }

    func bump(_ id: CGWindowID) {
        guard order.first != id else { return }
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
        if order.count > 400 { order.removeLast(order.count - 400) }
    }

    /// Sort windows by MRU. Windows never seen are appended in the order given.
    func sorted(_ windows: [WindowInfo]) -> [WindowInfo] {
        var rank: [CGWindowID: Int] = [:]
        for (i, id) in order.enumerated() { rank[id] = i }
        return windows.enumerated()
            .sorted { a, b in
                let ra = rank[a.element.id] ?? Int.max - a.offset
                let rb = rank[b.element.id] ?? Int.max - b.offset
                return ra == rb ? a.offset < b.offset : ra < rb
            }
            .map(\.element)
    }
}
