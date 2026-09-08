import AppKit

/// The thumbnail stack's layout is the single source of truth for both the
/// panel's size and the swipe gesture's hit testing, so the two cannot drift.
@MainActor
func runThumbnailTests(_ runner: inout TestRunner) {
    runner.section("Thumbnail layout")

    let settings = TestFixtures.makeSettings(suite: "com.screenshotbooster.tests.thumbnails")
    let library = ScreenshotLibrary(settings: settings)
    let image = TestFixtures.quadrantImage(width: 400, height: 250)
    for _ in 0..<3 { _ = try? library.add(image: image, scale: 2, mode: .area, sourceName: nil) }
    defer { library.removeAll() }

    guard library.screenshots.count == 3 else {
        runner.expect(false, "three screenshots are pinned")
        return
    }
    let width = CGFloat(settings.thumbnailWidth)
    let newest = library.screenshots.last!
    let oldest = library.screenshots.first!

    for corner in PanelCorner.allCases {
        let layout = ThumbnailGeometry.layout(for: library.screenshots, width: width, corner: corner)
        let size = ThumbnailGeometry.contentSize(for: library.screenshots, width: width, corner: corner)
        runner.expect(layout.size == size, "\(corner.title): the panel size comes from the layout")
        runner.expect(layout.cardRects.count == 3, "\(corner.title): every card is placed")

        // The newest shot sits closest to the anchored corner.
        let sorted = layout.cardRects.sorted { $0.rect.minY < $1.rect.minY }
        let nearestCorner = corner.isBottom ? sorted.last : sorted.first
        runner.expect(nearestCorner?.id == newest.id,
                      "\(corner.title): the newest shot is closest to the corner")
        runner.expect((corner.isBottom ? sorted.first : sorted.last)?.id == oldest.id,
                      "\(corner.title): the oldest is furthest from it")

        // Cards never overlap.
        var overlaps = false
        for (index, entry) in layout.cardRects.enumerated() {
            for other in layout.cardRects[(index + 1)...] where entry.rect.intersects(other.rect) {
                overlaps = true
            }
        }
        runner.expect(!overlaps, "\(corner.title): cards do not overlap")

        // Every card is reachable, and the header strip belongs to no card.
        var reachable = 0
        for entry in layout.cardRects where layout.card(at: CGPoint(x: entry.rect.midX, y: entry.rect.midY)) == entry.id {
            reachable += 1
        }
        runner.expect(reachable == 3, "\(corner.title): every card can be hit at its centre")

        let headerY = corner.stackGrowsUpwards
            ? ThumbnailGeometry.padding + ThumbnailGeometry.headerHeight / 2
            : layout.size.height - ThumbnailGeometry.padding - ThumbnailGeometry.headerHeight / 2
        runner.expect(layout.card(at: CGPoint(x: layout.size.width / 2, y: headerY)) == nil,
                      "\(corner.title): the header strip is not part of a card")
        runner.expect(layout.card(at: CGPoint(x: 2, y: layout.size.height / 2)) == nil,
                      "\(corner.title): the outer padding falls through")
    }

    runner.section("Thumbnail swipe")

    let interaction = ThumbnailInteractionModel()
    var dismissed: [UUID] = []
    let layout = ThumbnailGeometry.layout(for: library.screenshots, width: width, corner: .bottomLeft)
    let recognizer = ThumbnailSwipeRecognizer(model: interaction,
                                              layout: { layout },
                                              dismiss: { dismissed.append($0) })

    // The pointer arrives in AppKit coordinates, bottom-left origin.
    let height = layout.size.height
    let cardHeight = ThumbnailGeometry.cardHeight(for: newest, width: width)
    let nearBottom = CGPoint(x: ThumbnailGeometry.padding + width / 2,
                             y: ThumbnailGeometry.padding + cardHeight / 2)
    runner.expect(recognizer.card(atContentPoint: nearBottom, contentHeight: height) == newest.id,
                  "a pointer near the bottom of the panel targets the newest card")

    let scrolled = recognizer.card(atContentPoint: CGPoint(x: width / 2, y: height / 2),
                                   contentHeight: height,
                                   scrollOffset: cardHeight + ThumbnailGeometry.spacing)
    let unscrolled = recognizer.card(atContentPoint: CGPoint(x: width / 2, y: height / 2),
                                     contentHeight: height)
    runner.expect(scrolled != unscrolled, "scrolling the stack changes which card is under the pointer")

    interaction.swipe = .init(id: newest.id, offset: -40)
    runner.expect(interaction.offset(for: newest.id) == -40 && interaction.offset(for: oldest.id) == 0,
                  "the swipe offset reaches only the card being swiped")
    interaction.clear(if: newest.id)
    runner.expect(interaction.swipe == nil, "clearing the swipe resets it")
}
