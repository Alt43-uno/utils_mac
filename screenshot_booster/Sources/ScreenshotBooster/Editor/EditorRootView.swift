import SwiftUI

/// Editor window content: toolbar, canvas, status bar.
struct EditorRootView: View {
    @ObservedObject var model: EditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbarView(model: model)
            Divider()
            CanvasRepresentable(model: model)
                .background(Color(nsColor: .underPageBackgroundColor))
            Divider()
            statusBar
        }
        .frame(minWidth: 900, minHeight: 480)
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Label(model.screenshot.displayTitle, systemImage: model.screenshot.mode.symbolName)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .layoutPriority(1)
            Text("\(Int(model.outputSize.width)) × \(Int(model.outputSize.height)) px")
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer()

            if let status = model.status {
                Label(status.text, systemImage: status.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(status.isError ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                Text(hint)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(.bar)
        .animation(.easeInOut(duration: 0.18), value: model.status)
    }

    private var hint: String {
        switch model.tool {
        case .select: return "Drag to move · handles to resize · ⌫ to delete"
        case .crop: return "Drag a region · ⎋ resets the crop"
        case .text: return "Click to place text · ↩ to finish · ⌥↩ for a new line"
        default: return "Hold ⇧ to constrain · V returns to the selection tool"
        }
    }
}
