import SwiftUI
import UniformTypeIdentifiers

/// One pinned screenshot: click to edit, ✕ to dismiss, drag to share, right
/// click for everything else.
struct ThumbnailItemView: View {
    let screenshot: Screenshot
    let width: CGFloat
    let actions: ThumbnailActions
    @ObservedObject var interaction: ThumbnailInteractionModel

    @State private var isHovering = false

    /// How far this card has been swiped, if it is the one being swiped.
    private var swipeOffset: CGFloat { interaction.offset(for: screenshot.id) }

    private var height: CGFloat {
        ThumbnailGeometry.cardHeight(for: screenshot, width: width)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            card
            closeButton
                .padding(5)
        }
        .frame(width: width, height: height)
        .offset(x: swipeOffset)
        .opacity(1 - min(abs(swipeOffset) / 220, 0.8))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .contextMenu { contextMenu }
        .onDrag(makeItemProvider, preview: dragPreview)
        .help(helpText)
    }

    // MARK: - Pieces

    private var card: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ThumbnailGeometry.cornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))

            if let image = actions.thumbnailImage(screenshot) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }

            if isHovering {
                LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.45)],
                               startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
                caption
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: ThumbnailGeometry.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ThumbnailGeometry.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: ThumbnailGeometry.cornerRadius, style: .continuous))
        // A plain tap gesture (rather than a Button) so it never competes with
        // the drag gesture that `.onDrag` installs.
        .onTapGesture { actions.open(screenshot) }
    }

    private var caption: some View {
        VStack {
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: screenshot.mode.symbolName)
                Text(screenshot.dimensionsLabel)
                Spacer()
                if screenshot.hasEdits {
                    Image(systemName: "pencil.circle.fill")
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .allowsHitTesting(false)
    }

    private var closeButton: some View {
        Button {
            actions.delete(screenshot)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 17, height: 17)
                .background(Circle().fill(Color.black.opacity(isHovering ? 0.75 : 0.45)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .opacity(isHovering ? 1 : 0.65)
        .help("Remove this screenshot")
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Edit…") { actions.open(screenshot) }
        Button("Copy") { actions.copy(screenshot) }
        Divider()
        Button("Save") { actions.save(screenshot) }
        Button("Save As…") { actions.saveAs(screenshot) }
        Button("Reveal in Finder") { actions.reveal(screenshot) }
        Divider()
        Button("Delete") { actions.delete(screenshot) }
        Button("Clear All") { actions.clearAll() }
    }

    // MARK: - Drag & drop

    private func makeItemProvider() -> NSItemProvider {
        guard let url = actions.dragFileURL(screenshot),
              let provider = NSItemProvider(contentsOf: url) else {
            return NSItemProvider()
        }
        // Suggesting a name makes drops into Finder and chat apps land with a
        // readable file name instead of a UUID.
        provider.suggestedName = url.lastPathComponent
        return provider
    }

    @ViewBuilder
    private func dragPreview() -> some View {
        if let image = actions.thumbnailImage(screenshot) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: ThumbnailGeometry.cornerRadius, style: .continuous))
        } else {
            Color.clear.frame(width: width, height: height)
        }
    }

    private var helpText: String {
        "\(screenshot.displayTitle) · \(screenshot.dimensionsLabel)\nClick to edit · drag to share · swipe left to dismiss"
    }
}
