import SwiftUI

/// Metrics for the floating glass controls that hover over the canvas.
///
/// The canvas lays the screenshot out inside whatever these leave free, so both
/// sides read the numbers from here and can never drift apart.
enum EditorChrome {
    /// Gap between a pill and the window edge.
    static let margin: CGFloat = 12
    /// Space between neighbouring pills.
    static let spacing: CGFloat = 8
    /// Room for the window's traffic lights, which the top row sits level with.
    static let trafficLightInset: CGFloat = 84

    static let toolbarHeight: CGFloat = 36
    static let statusHeight: CGFloat = 28

    /// Lines the pills up with the vertical centre of the traffic lights.
    static let topMargin: CGFloat = 10

    static var topInset: CGFloat { topMargin + toolbarHeight + margin }
    static var bottomInset: CGFloat { margin + statusHeight + margin }
}

extension View {
    /// Wraps the view in a floating Liquid Glass capsule.
    func editorPill(horizontalPadding: CGFloat = 8) -> some View {
        padding(.horizontal, horizontalPadding)
            .frame(height: EditorChrome.toolbarHeight)
            .glassEffect(.regular, in: .capsule)
    }
}
