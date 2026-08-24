import SwiftUI

/// Shared state between the SwiftUI thumbnail stack and the AppKit code that
/// recognises the two-finger swipe: the recogniser writes the offset, the card
/// reads it.
@MainActor
final class ThumbnailInteractionModel: ObservableObject {

    /// The card being swiped and how far it has travelled, in points.
    struct Swipe: Equatable {
        var id: UUID
        var offset: CGFloat
    }

    @Published var swipe: Swipe?

    func offset(for id: UUID) -> CGFloat {
        guard let swipe, swipe.id == id else { return 0 }
        return swipe.offset
    }

    func clear(if id: UUID) {
        if swipe?.id == id { swipe = nil }
    }
}
