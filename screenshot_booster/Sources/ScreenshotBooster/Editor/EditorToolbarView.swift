import SwiftUI

/// Top bar of the editor: tools on the left, style controls in the middle,
/// document actions on the right.
///
/// Every group shrinks gracefully — `ViewThatFits` drops the colour presets
/// before anything important is clipped — so the window stays usable at its
/// minimum width.
struct EditorToolbarView: View {
    @ObservedObject var model: EditorViewModel

    /// Leaves room for the window's traffic lights, since the editor uses a
    /// full-size content view.
    private let trafficLightInset: CGFloat = 76

    var body: some View {
        HStack(spacing: 10) {
            toolGroup
            Divider().frame(height: 20)
            styleGroup
            Spacer(minLength: 4)
            actionGroup
        }
        .padding(.leading, trafficLightInset)
        .padding(.trailing, 10)
        .frame(height: 48)
        .background(.bar)
    }

    // MARK: - Groups

    private var toolGroup: some View {
        HStack(spacing: 1) {
            ForEach(ToolKind.editorOrder) { tool in
                ToolButton(tool: tool, isSelected: model.tool == tool) {
                    model.tool = tool
                }
            }
        }
        .layoutPriority(2)
    }

    /// Whether the style controls apply to the active tool or to the selection.
    private var styleTool: ToolKind {
        model.selectedAnnotation?.tool ?? model.tool
    }

    @ViewBuilder
    private var styleGroup: some View {
        HStack(spacing: 8) {
            if styleTool.usesColor {
                ViewThatFits(in: .horizontal) {
                    ColorControls(color: $model.color, presetCount: RGBAColor.presets.count)
                    ColorControls(color: $model.color, presetCount: 4)
                    ColorControls(color: $model.color, presetCount: 0)
                }
                .onChange(of: model.color) { _, _ in model.applyStyleToSelection() }
            }

            if styleTool == .text {
                StepperControl(value: $model.fontSize, range: 12...120, step: 2, systemImage: "textformat.size")
                    .onChange(of: model.fontSize) { _, _ in model.applyStyleToSelection() }
            } else if styleTool.usesLineWidth {
                StepperControl(value: $model.lineWidth, range: 1...32, step: 1, systemImage: "lineweight")
                    .onChange(of: model.lineWidth) { _, _ in model.applyStyleToSelection() }
            }
        }
        .layoutPriority(1)
    }

    private var actionGroup: some View {
        HStack(spacing: 4) {
            IconButton(systemImage: "arrow.uturn.backward", help: "Undo (⌘Z)", isEnabled: model.canUndo) {
                model.undo()
            }
            IconButton(systemImage: "arrow.uturn.forward", help: "Redo (⇧⌘Z)", isEnabled: model.canRedo) {
                model.redo()
            }
            IconButton(systemImage: "trash", help: "Delete selection (⌫)", isEnabled: model.selectedID != nil) {
                model.deleteSelection()
            }

            Divider().frame(height: 20)

            IconButton(systemImage: "doc.on.doc", help: "Copy to clipboard (⌘C)") {
                model.copyToClipboard()
            }

            Button {
                model.save()
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 22)
            }
            .buttonStyle(.borderedProminent)
            .help("Save (⌘S)")

            Menu {
                Button("Save As…") { model.saveAs() }
                Button("Copy to Clipboard") { model.copyToClipboard() }
                Divider()
                Button("Reset Crop") { model.applyCrop(nil) }
                    .disabled(model.document.cropRect == nil)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
            .help("More actions")
        }
        .layoutPriority(3)
        .fixedSize()
    }
}

// MARK: - Controls

private struct ToolButton: View {
    let tool: ToolKind
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tool.symbolName)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor
                                         : (isHovering ? Color.primary.opacity(0.09) : Color.clear))
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("\(tool.title) (\(tool.shortcutKey.uppercased()))")
    }
}

private struct IconButton: View {
    let systemImage: String
    let help: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .help(help)
    }
}

/// Colour presets plus a system colour well for anything else.
private struct ColorControls: View {
    @Binding var color: RGBAColor
    let presetCount: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(RGBAColor.presets.prefix(presetCount).enumerated()), id: \.offset) { _, preset in
                Button {
                    color = preset.withAlpha(color.alpha)
                } label: {
                    Circle()
                        .fill(preset.swiftUIColor)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle().strokeBorder(isSelected(preset) ? Color.primary : Color.primary.opacity(0.25),
                                                  lineWidth: isSelected(preset) ? 2 : 0.5)
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Use this colour")
            }
            CustomColorButton(color: $color)
        }
    }

    private func isSelected(_ preset: RGBAColor) -> Bool {
        abs(preset.red - color.red) < 0.02 &&
        abs(preset.green - color.green) < 0.02 &&
        abs(preset.blue - color.blue) < 0.02
    }
}

/// Small swatch that opens the system colour panel.
///
/// `ColorPicker` (and `NSColorWell`, even in its minimal style) render a control
/// far wider than a dense toolbar can afford, so this is a plain button wired to
/// `NSColorPanel`.
private struct CustomColorButton: View {
    @Binding var color: RGBAColor

    var body: some View {
        Button {
            ColorPanelController.shared.present(current: color) { color = $0 }
        } label: {
            ZStack {
                Circle()
                    .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                          center: .center))
                Circle()
                    .fill(color.swiftUIColor)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 0.5))
            }
            .frame(width: 14, height: 14)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Choose a custom colour")
    }
}

/// Bridges the shared `NSColorPanel` to whichever swatch opened it.
@MainActor
final class ColorPanelController: NSObject {
    static let shared = ColorPanelController()

    private var onChange: ((RGBAColor) -> Void)?

    private override init() {
        super.init()
        // Dropping the callback when the panel closes releases the editor it
        // belonged to.
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(panelWillClose(_:)),
                                              name: NSWindow.willCloseNotification,
                                              object: NSColorPanel.shared)
    }

    func present(current: RGBAColor, onChange: @escaping (RGBAColor) -> Void) {
        self.onChange = onChange
        let panel = NSColorPanel.shared
        panel.showsAlpha = true
        panel.color = current.nsColor
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.isFloatingPanel = true
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        onChange?(RGBAColor(sender.color))
    }

    @objc private func panelWillClose(_ notification: Notification) {
        onChange = nil
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)
    }
}

/// Compact numeric control used for line width and font size.
private struct StepperControl: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let step: CGFloat
    let systemImage: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Slider(value: $value, in: range, step: step)
                .controlSize(.small)
                .frame(width: 76)
            Text("\(Int(value))")
                .font(.system(size: 11, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
        }
        .fixedSize()
    }
}
