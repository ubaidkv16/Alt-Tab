import CoreGraphics

/// Deterministic grid geometry, shared by the SwiftUI view and the panel frame
/// so the window is sized exactly to its content (no layout pass round-trip).
struct SwitcherLayout: Equatable {
    static let padding: CGFloat = 18
    static let spacing: CGFloat = 12

    var tile: CGSize = .zero
    var columns: Int = 1
    var rows: Int = 1
    var panelSize: CGSize = .zero
    var thumbHeight: CGFloat = 0

    static let empty = SwitcherLayout()

    init() {}

    init(count: Int, tileWidth: CGFloat, showTitles: Bool, maxWidth: CGFloat, maxHeight: CGFloat) {
        let count = max(count, 1)
        thumbHeight = (tileWidth * 0.6).rounded()
        let tileHeight = 8 + thumbHeight + 6 + 22 + (showTitles ? 15 : 0) + 8
        tile = CGSize(width: tileWidth, height: tileHeight)

        let usable = maxWidth - Self.padding * 2
        let perColumn = tileWidth + Self.spacing
        columns = max(1, min(count, Int((usable + Self.spacing) / perColumn)))
        rows = Int((Double(count) / Double(columns)).rounded(.up))

        // Never grow past the display.
        let maxRows = max(1, Int((maxHeight - Self.padding * 2 + Self.spacing) / (tileHeight + Self.spacing)))
        rows = min(rows, maxRows)

        panelSize = CGSize(
            width: Self.padding * 2 + CGFloat(columns) * tileWidth + CGFloat(columns - 1) * Self.spacing,
            height: Self.padding * 2 + CGFloat(rows) * tileHeight + CGFloat(rows - 1) * Self.spacing
        )
    }
}
