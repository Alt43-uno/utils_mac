import AppKit
import SwiftUI

/// Click-to-record shortcut field.
final class ShortcutRecorderNSView: NSView {

    var combo: KeyCombo? {
        didSet { needsDisplay = true }
    }
    var onChange: ((KeyCombo?) -> Void)?

    private var isRecording = false {
        didSet { needsDisplay = true }
    }
    private var liveModifiers: NSEvent.ModifierFlags = []

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 24) }

    // MARK: - Interaction

    override func mouseDown(with event: NSEvent) {
        guard !isRecording else {
            stopRecording()
            return
        }
        window?.makeFirstResponder(self)
        isRecording = true
        liveModifiers = []
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return true
    }

    private func stopRecording() {
        isRecording = false
        liveModifiers = []
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return super.flagsChanged(with: event) }
        liveModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        needsDisplay = true
    }

    /// Intercepts ⌘-based combinations before the main menu can claim them.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        return handle(event)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording, handle(event) else {
            super.keyDown(with: event)
            return
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case 53: // Escape cancels recording
            stopRecording()
            return true
        case 51, 117: // Delete clears the shortcut
            combo = nil
            onChange?(nil)
            stopRecording()
            return true
        default:
            break
        }

        let candidate = KeyCombo(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
        guard candidate.isValid else {
            NSSound.beep()
            return true
        }
        combo = candidate
        onChange?(candidate)
        stopRecording()
        return true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let rounded = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.14)
                     : NSColor.controlBackgroundColor).setFill()
        rounded.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        rounded.lineWidth = isRecording ? 1.5 : 1
        rounded.stroke()

        let text: String
        if isRecording {
            text = liveModifiers.isEmpty ? "Press keys…" : KeyCombo.modifierString(liveModifiers)
        } else {
            text = combo?.displayString ?? "Click to record"
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: combo == nil ? .regular : .medium),
            .foregroundColor: isRecording ? NSColor.controlAccentColor
                                          : (combo == nil ? NSColor.secondaryLabelColor : NSColor.labelColor)
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                            y: (bounds.height - size.height) / 2),
                                withAttributes: attributes)
    }
}

/// SwiftUI wrapper for the recorder.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var combo: KeyCombo?

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.combo = combo
        view.onChange = { newValue in combo = newValue }
        return view
    }

    func updateNSView(_ view: ShortcutRecorderNSView, context: Context) {
        if view.combo != combo { view.combo = combo }
        view.onChange = { newValue in combo = newValue }
    }
}
