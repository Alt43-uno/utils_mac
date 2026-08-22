import SwiftUI

/// The vertical stack of pinned screenshots shown in the floating panel.
struct ThumbnailStackView: View {
    @ObservedObject var library: ScreenshotLibrary
    @ObservedObject var settings: SettingsStore
    let actions: ThumbnailActions

    private var width: CGFloat { CGFloat(settings.thumbnailWidth) }

    /// Newest shots sit closest to the anchored corner.
    private var orderedScreenshots: [Screenshot] {
        settings.panelCorner.stackGrowsUpwards ? library.screenshots.reversed() : library.screenshots
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: ThumbnailGeometry.spacing) {
                if library.screenshots.count > 1, !settings.panelCorner.stackGrowsUpwards {
                    header
                }
                ForEach(orderedScreenshots) { screenshot in
                    ThumbnailItemView(screenshot: screenshot, width: width, actions: actions)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.82).combined(with: .opacity),
                            removal: .scale(scale: 0.9).combined(with: .opacity)
                        ))
                }
                if library.screenshots.count > 1, settings.panelCorner.stackGrowsUpwards {
                    header
                }
            }
            .padding(ThumbnailGeometry.padding)
            .frame(width: width + ThumbnailGeometry.padding * 2, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: library.screenshots.map(\.id))
        .background(Color.clear)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("\(library.screenshots.count) shots")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            Spacer(minLength: 4)
            Button("Clear") { actions.clearAll() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 9)
        .frame(width: width, height: ThumbnailGeometry.headerHeight)
        .background(
            Capsule(style: .continuous)
                .fill(.black.opacity(0.55))
        )
        .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
    }
}
