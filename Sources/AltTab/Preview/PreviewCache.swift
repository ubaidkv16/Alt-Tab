import AppKit
import ScreenCaptureKit

/// Thumbnails of live windows, captured with ScreenCaptureKit on demand only.
///
/// Nothing is captured while the switcher is closed, so idle CPU is zero.
/// Images are cached per window id and only re-captured when stale.
@MainActor
final class PreviewCache: ObservableObject {
    static let shared = PreviewCache()

    /// Bumped whenever a new thumbnail lands so SwiftUI redraws.
    @Published private(set) var version = 0

    private var images: [CGWindowID: CGImage] = [:]
    private var captured: [CGWindowID: Date] = [:]
    private var busy = false

    private let maxEntries = 80
    private let staleAfter: TimeInterval = 4

    func image(for id: CGWindowID) -> CGImage? { images[id] }

    /// Capture anything missing or stale. Progressive: the UI fills in as shots arrive.
    func warm(_ windows: [WindowInfo], targetWidth: CGFloat, scale: CGFloat) {
        guard !busy, CGPreflightScreenCaptureAccess() else { return }
        let now = Date()
        let wanted = windows.filter { w in
            guard !w.isMinimized else { return false }
            guard let t = captured[w.id] else { return true }
            return now.timeIntervalSince(t) > staleAfter
        }
        guard !wanted.isEmpty else { return }
        busy = true

        Task { [weak self] in
            defer { self?.busy = false }
            guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else { return }
            var byID: [CGWindowID: SCWindow] = [:]
            for w in content.windows { byID[w.windowID] = w }

            for info in wanted {
                guard let scWindow = byID[info.id] else { continue }
                guard let image = await Self.capture(scWindow, targetWidth: targetWidth * scale) else { continue }
                self?.store(image, for: info.id)
            }
        }
    }

    private static func capture(_ window: SCWindow, targetWidth: CGFloat) async -> CGImage? {
        let size = window.frame.size
        guard size.width > 1, size.height > 1 else { return nil }
        let width = min(targetWidth, size.width * 2)
        let height = max(1, (width / size.width) * size.height)

        let config = SCStreamConfiguration()
        config.width = Int(width.rounded())
        config.height = Int(height.rounded())
        config.showsCursor = false
        config.scalesToFit = true

        let filter = SCContentFilter(desktopIndependentWindow: window)
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    func store(_ image: CGImage, for id: CGWindowID) {
        images[id] = image
        captured[id] = Date()
        if images.count > maxEntries, let oldest = captured.min(by: { $0.value < $1.value })?.key {
            images.removeValue(forKey: oldest)
            captured.removeValue(forKey: oldest)
        }
        version &+= 1
    }

    func forget(idsNotIn live: Set<CGWindowID>) {
        for id in images.keys where !live.contains(id) {
            images.removeValue(forKey: id)
            captured.removeValue(forKey: id)
        }
    }
}
