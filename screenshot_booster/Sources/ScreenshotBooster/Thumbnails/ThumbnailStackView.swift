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

    /// Lets neighbouring glass surfaces merge and morph as cards come and go.
    @Namespace private var glassNamespace

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                GlassEffectContainer(spacing: ThumbnailGeometry.spacing) {
                    VStack(alignment: .leading, spacing: ThumbnailGeometry.spacing) {
                        // The header goes at the far end from the anchored corner
                        // so the cards stay closest to the screen edge.
                        if showsHeader, settings.panelCorner.stackGrowsUpwards { header }

                        ForEach(orderedScreenshots) { screenshot in
                            ThumbnailItemView(screenshot: screenshot,
                                              width: width,
                                              actions: actions,
                                              interaction: interaction)
                                .id(screenshot.id)
                                .glassEffectID(screenshot.id, in: glassNamespace)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.82).combined(with: .opacity),
                                    removal: .scale(scale: 0.9).combined(with: .opacity)
                                ))
                        }

                        if showsHeader, !settings.panelCorner.stackGrowsUpwards { header }
                    }
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
            Spacer(minLength: 4)
            Button("Clear") { actions.clearAll() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: ThumbnailGeometry.headerHeight)
        .glassEffect(.regular, in: .capsule)
    }
}
