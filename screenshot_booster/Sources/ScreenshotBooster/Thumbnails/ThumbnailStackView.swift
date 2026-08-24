import SwiftUI

/// The vertical stack of pinned screenshots shown in the floating panel.
struct ThumbnailStackView: View {
    @ObservedObject var library: ScreenshotLibrary
    @ObservedObject var settings: SettingsStore
    @ObservedObject var interaction: ThumbnailInteractionModel
    let actions: ThumbnailActions

    private var width: CGFloat { CGFloat(settings.thumbnailWidth) }

    /// The newest shot always sits closest to the anchored corner: at the bottom
    /// of the stack for the bottom corners, at the top for the top corners.
    private var orderedScreenshots: [Screenshot] {
        ThumbnailGeometry.orderedScreenshots(library.screenshots, corner: settings.panelCorner)
    }

    /// The shot the stack should keep in view when a new one arrives.
    private var newestID: UUID? { library.screenshots.last?.id }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: ThumbnailGeometry.spacing) {
                    // The header goes at the far end from the anchored corner so
                    // the cards themselves stay closest to the screen edge.
                    if showsHeader, settings.panelCorner.stackGrowsUpwards { header }

                    ForEach(orderedScreenshots) { screenshot in
                        ThumbnailItemView(screenshot: screenshot,
                                          width: width,
                                          actions: actions,
                                          interaction: interaction)
                            .id(screenshot.id)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.82).combined(with: .opacity),
                                removal: .scale(scale: 0.9).combined(with: .opacity)
                            ))
                    }

                    if showsHeader, !settings.panelCorner.stackGrowsUpwards { header }
                }
                .padding(ThumbnailGeometry.padding)
                .frame(width: width + ThumbnailGeometry.padding * 2, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .animation(.spring(response: 0.34, dampingFraction: 0.78), value: library.screenshots.map(\.id))
            .background(Color.clear)
            .onChange(of: newestID) { _, id in
                // Once the stack is taller than the screen it scrolls; the shot
                // that was just taken must stay visible.
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: settings.panelCorner.stackGrowsUpwards ? .bottom : .top)
                }
            }
        }
    }

    private var showsHeader: Bool { library.screenshots.count > 1 }

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
