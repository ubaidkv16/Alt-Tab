import AppKit
import SwiftUI

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    @ObservedObject var settings = Settings.shared
    @ObservedObject var previews = PreviewCache.shared

    var onPick: (Int) -> Void
    var onHover: (Int) -> Void

    var body: some View {
        VStack(spacing: SwitcherLayout.spacing) {
            ForEach(0..<model.layout.rows, id: \.self) { row in
                HStack(spacing: SwitcherLayout.spacing) {
                    ForEach(indices(in: row), id: \.self) { index in
                        tile(index)
                    }
                    if indices(in: row).count < model.layout.columns && model.layout.rows > 1 {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(SwitcherLayout.padding)
        .frame(width: model.layout.panelSize.width, height: model.layout.panelSize.height)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: settings.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: settings.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private var background: some View {
        Group {
            if settings.blurEnabled {
                VisualEffect()
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .opacity(settings.backgroundOpacity)
    }

    private func indices(in row: Int) -> [Int] {
        let start = row * model.layout.columns
        let end = min(start + model.layout.columns, model.windows.count)
        return start < end ? Array(start..<end) : []
    }

    @ViewBuilder
    private func tile(_ index: Int) -> some View {
        let window = model.windows[index]
        let isSelected = index == model.selected

        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                thumbnail(window)
                    .padding(2)
            }
            .frame(width: model.layout.tile.width - 16, height: model.layout.thumbHeight)

            HStack(spacing: 5) {
                if settings.showIcons, let icon = window.icon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
                Text(window.appName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if window.isMinimized {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 16)

            if settings.showTitles {
                Text(window.displayTitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: 12)
            }
        }
        .padding(8)
        .frame(width: model.layout.tile.width, height: model.layout.tile.height)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(isSelected ? 0.30 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(isSelected ? 0.95 : 0), lineWidth: 2)
        )
        .opacity(window.isMinimized && !isSelected ? 0.62 : 1)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .contentShape(Rectangle())
        .onHover { if $0 { onHover(index) } }
        .onTapGesture { onPick(index) }
    }

    @ViewBuilder
    private func thumbnail(_ window: WindowInfo) -> some View {
        if let cg = previews.image(for: window.id) {
            Image(decorative: cg, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else if let icon = window.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: model.layout.thumbHeight * 0.62)
        } else {
            Image(systemName: "macwindow").font(.largeTitle).foregroundStyle(.secondary)
        }
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
