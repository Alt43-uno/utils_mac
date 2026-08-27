import SwiftUI

/// Editor window content: toolbar, canvas, status bar.
struct EditorRootView: View {
    @ObservedObject var model: EditorViewModel

    var body: some View {
        // The canvas runs edge to edge and the bars float on top of it: glass
        // needs something behind it to refract, and an opaque window background
        // gives it nothing.
        ZStack(alignment: .top) {
            // Transparent window: what shows through is the blurred desktop and
            // whatever windows are behind, darkened just enough to read against.
            WindowBackdropView()
                .overlay(Color.black.opacity(0.28))

            CanvasRepresentable(model: model)

            VStack(spacing: 0) {
                EditorToolbarView(model: model)
                Spacer(minLength: 0)
                statusBar
            }
        }
        // The window uses a full-size content view, so the controls belong level
        // with the traffic lights rather than pushed below the title bar.
        .ignoresSafeArea()
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

            zoomControls

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
        .padding(.horizontal, 14)
        .frame(height: EditorChrome.statusHeight)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, EditorChrome.margin)
        .padding(.bottom, EditorChrome.margin)
        .animation(.easeInOut(duration: 0.18), value: model.status)
    }

    /// Compact zoom stepper: −, the current percentage as a menu, +.
    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button { model.zoomOut() } label: {
                Image(systemName: "minus")
                    .frame(width: 18, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!model.canZoomOut)
            .help("Zoom out (⌘−)")

            Menu {
                Button("Zoom to Fit") { model.zoomToFit() }
                Button("Actual Size") { model.zoomToActualSize() }
                Divider()
                ForEach([50, 100, 200, 400], id: \.self) { percent in
                    Button("\(percent)%") { model.setVisualScale(CGFloat(percent) / 100) }
                }
            } label: {
                Text(model.zoomMode == .fit ? "Fit · \(model.zoomPercent)%" : "\(model.zoomPercent)%")
                    .monospacedDigit()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Zoom level")

            Button { model.zoomIn() } label: {
                Image(systemName: "plus")
                    .frame(width: 18, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!model.canZoomIn)
            .help("Zoom in (⌘+)")
        }
        .foregroundStyle(.secondary)
    }

    private var hint: String {
        switch model.tool {
        case .select: return "Drag to move · handles to resize · ⌫ to delete · pinch to zoom"
        case .crop: return "Drag a region · ⎋ resets the crop"
        case .text: return "Click to place text · ↩ to finish · ⌥↩ for a new line"
        default: return "Hold ⇧ to constrain · V returns to the selection tool"
        }
    }
}
