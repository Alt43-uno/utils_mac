import SwiftUI

/// Bridges the AppKit canvas into the SwiftUI editor layout.
struct CanvasRepresentable: NSViewRepresentable {
    @ObservedObject var model: EditorViewModel

    func makeNSView(context: Context) -> CanvasView {
        CanvasView(model: model)
    }

    func updateNSView(_ view: CanvasView, context: Context) {
        // Leaving the text tool (or the document changing underneath) must close
        // any inline editor before the canvas redraws.
        if view.isEditingText, model.tool != .text, model.tool != .select {
            view.endTextEditing(commit: true)
        }
        view.syncZoomState()
        view.needsDisplay = true
    }

    static func dismantleNSView(_ view: CanvasView, coordinator: ()) {
        view.endTextEditing(commit: true)
    }
}
