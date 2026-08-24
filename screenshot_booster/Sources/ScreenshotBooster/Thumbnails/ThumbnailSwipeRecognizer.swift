import AppKit
import SwiftUI

/// Recognises a two-finger swipe to the left over a thumbnail and dismisses it.
///
/// Trackpad swipes arrive as precise scroll events, not as mouse drags, so this
/// listens for `.scrollWheel` with a local event monitor rather than fighting
/// SwiftUI's gesture system — which leaves `.onDrag` (dragging a screenshot out
/// to another app) completely untouched.
@MainActor
final class ThumbnailSwipeRecognizer {

    /// How far a card has to travel before releasing dismisses it.
    private let dismissThreshold: CGFloat = 52
    /// Rubber-band factor applied when swiping the "wrong" way.
    private let resistance: CGFloat = 0.25

    private let model: ThumbnailInteractionModel
    private let layout: () -> ThumbnailGeometry.Layout
    private let dismiss: (UUID) -> Void

    private weak var panel: NSPanel?
    private var monitor: Any?
    private var activeID: UUID?
    private var travelled: CGFloat = 0
    /// Set once a gesture has been claimed as vertical, so the stack keeps
    /// scrolling normally for the rest of that gesture.
    private var isScrollingVertically = false

    init(model: ThumbnailInteractionModel,
         layout: @escaping () -> ThumbnailGeometry.Layout,
         dismiss: @escaping (UUID) -> Void) {
        self.model = model
        self.layout = layout
        self.dismiss = dismiss
    }

    // MARK: - Lifecycle

    func attach(to panel: NSPanel) {
        detach()
        self.panel = panel
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func detach() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        panel = nil
        reset()
    }

    private func reset() {
        activeID = nil
        travelled = 0
        isScrollingVertically = false
    }

    // MARK: - Recognition

    /// Returns `true` when the event was consumed by the swipe.
    private func handle(_ event: NSEvent) -> Bool {
        guard let panel, event.window === panel else { return false }
        // Only trackpads produce precise deltas; a mouse wheel should never
        // throw a screenshot away.
        guard event.hasPreciseScrollingDeltas, event.momentumPhase == [] else { return false }

        switch event.phase {
        case .began:
            reset()
            return false

        case .ended, .cancelled:
            defer { reset() }
            guard let id = activeID else { return false }
            finish(id: id)
            return true

        case .changed:
            return track(event)

        default:
            return false
        }
    }

    private func track(_ event: NSEvent) -> Bool {
        guard !isScrollingVertically else { return false }

        let horizontal = horizontalDelta(of: event)

        if activeID == nil {
            // Claim the gesture only once its direction is unambiguous.
            guard abs(horizontal) > abs(event.scrollingDeltaY) * 1.4, abs(horizontal) > 1 else {
                if abs(event.scrollingDeltaY) > 1 { isScrollingVertically = true }
                return false
            }
            guard let id = cardUnderPointer() else {
                isScrollingVertically = true
                return false
            }
            activeID = id
            travelled = 0
        }

        guard let id = activeID else { return false }
        // Swiping right just stretches a little: dismissal is a left gesture.
        travelled += horizontal > 0 && travelled >= 0 ? horizontal * resistance : horizontal
        travelled = min(travelled, 24)
        model.swipe = ThumbnailInteractionModel.Swipe(id: id, offset: travelled)
        return true
    }

    private func finish(id: UUID) {
        guard travelled <= -dismissThreshold else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                model.swipe = nil
            }
            return
        }

        // Fling the card off the edge, then unpin it for real.
        withAnimation(.easeIn(duration: 0.16)) {
            model.swipe = ThumbnailInteractionModel.Swipe(id: id, offset: -420)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.model.clear(if: id)
                self.dismiss(id)
            }
        }
    }

    // MARK: - Geometry

    /// Horizontal movement in "card follows your fingers" terms, regardless of
    /// the system's natural-scrolling preference.
    private func horizontalDelta(of event: NSEvent) -> CGFloat {
        event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
    }

    /// The card under the pointer.
    private func cardUnderPointer() -> UUID? {
        guard let panel, let contentView = panel.contentView else { return nil }
        let inWindow = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        let inContent = contentView.convert(inWindow, from: nil)
        return card(atContentPoint: inContent,
                    contentHeight: contentView.bounds.height,
                    scrollOffset: scrollOffset(in: contentView))
    }

    /// Maps a point in the panel's content view (AppKit, bottom-left origin)
    /// onto the stack's layout (top-left origin), accounting for scrolling.
    func card(atContentPoint point: CGPoint, contentHeight: CGFloat, scrollOffset: CGFloat = 0) -> UUID? {
        let inStack = CGPoint(x: point.x, y: contentHeight - point.y + scrollOffset)
        return layout().card(at: inStack)
    }

    /// How far the stack is scrolled from the top, in points.
    private func scrollOffset(in contentView: NSView) -> CGFloat {
        guard let scrollView = Self.findScrollView(in: contentView) else { return 0 }
        let clip = scrollView.contentView
        let origin = clip.bounds.origin.y
        guard clip.documentView?.isFlipped != true else { return origin }
        let documentHeight = clip.documentView?.bounds.height ?? clip.bounds.height
        return max(0, documentHeight - clip.bounds.height - origin)
    }

    private static func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for subview in view.subviews {
            if let found = findScrollView(in: subview) { return found }
        }
        return nil
    }
}
