import AppKit

/// Mouse, keyboard and inline-text handling for the editing canvas.
extension CanvasView {

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if textEditor != nil {
            endTextEditing(commit: true)
            return
        }

        let rawPoint = imagePoint(fromView: convert(event.locationInWindow, from: nil))
        let point = clampedToImage(rawPoint)
        model.endCoalescing()

        switch model.tool {
        case .select:
            beginSelectionInteraction(at: rawPoint, clickCount: event.clickCount)
        case .crop:
            interaction = .cropping(origin: point, rect: CGRect(origin: point, size: .zero))
        case .text:
            createTextAnnotation(at: point)
        default:
            let annotation = Annotation(tool: model.tool,
                                        points: [point, point],
                                        color: currentColor,
                                        lineWidth: model.lineWidth,
                                        fontSize: model.fontSize)
            interaction = .drawing(annotation)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let rawPoint = imagePoint(fromView: convert(event.locationInWindow, from: nil))
        let shift = event.modifierFlags.contains(.shift)
        // Drawing and cropping stay inside the image; moving an existing object
        // may legitimately take it past the edge.
        let point: CGPoint
        switch interaction {
        case .drawing, .cropping: point = clampedToImage(rawPoint)
        case .moving, .resizing, .none: point = rawPoint
        }

        switch interaction {
        case .drawing(var annotation):
            if annotation.tool.isPathBased {
                // Skip samples that are too close together: fewer points make
                // smoother curves and much cheaper hit testing.
                if let last = annotation.points.last, last.distance(to: point) < (1.5 / max(zoom, 0.05)) { return }
                annotation.points.append(point)
            } else {
                annotation.points = [annotation.points[0], constrained(point, from: annotation.points[0], shift: shift, tool: annotation.tool)]
            }
            interaction = .drawing(annotation)

        case .moving(let original, let grabPoint):
            var delta = CGVector(dx: point.x - grabPoint.x, dy: point.y - grabPoint.y)
            if shift {
                // Constrain to the dominant axis.
                if abs(delta.dx) > abs(delta.dy) { delta.dy = 0 } else { delta.dx = 0 }
            }
            interactionPreview = original.translated(dx: delta.dx, dy: delta.dy)

        case .resizing(let original, let handle, let originalBounds):
            if handle.isEndpoint {
                var updated = original
                let target = constrained(point, from: handle == .start ? original.end : original.start, shift: shift, tool: original.tool)
                if handle == .start {
                    updated.points = [target, original.end]
                } else {
                    updated.points = [original.start, target]
                }
                interactionPreview = updated
            } else {
                var newBounds = handle.resize(originalBounds, to: point)
                if shift, originalBounds.height > 0 {
                    let aspect = originalBounds.width / originalBounds.height
                    newBounds.size.height = newBounds.width / max(aspect, 0.0001)
                }
                newBounds = newBounds.expandedToMinimum(4)
                interactionPreview = original.resized(from: originalBounds, to: newBounds)
            }

        case .cropping(let origin, _):
            var rect = CGRect(corner: origin, opposite: point)
            if shift {
                let side = max(rect.width, rect.height)
                rect = CGRect(x: point.x < origin.x ? origin.x - side : origin.x,
                              y: point.y < origin.y ? origin.y - side : origin.y,
                              width: side, height: side)
            }
            interaction = .cropping(origin: origin, rect: rect.clamped(to: model.document.baseBounds))

        case .none:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch interaction {
        case .drawing(let annotation):
            commitDrawn(annotation)

        case .moving(let original, _), .resizing(let original, _, _):
            if let preview = interactionPreview, preview != original {
                model.replaceAnnotation(preview)
            }

        case .cropping(_, let rect):
            if rect.width >= 8, rect.height >= 8 {
                model.applyCrop(rect)
            }

        case .none:
            break
        }
        interaction = .none
        interactionPreview = nil
        model.endCoalescing()
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(for: imagePoint(fromView: convert(event.locationInWindow, from: nil)))
    }

    /// Middle-button drag pans, the way most image editors do it.
    override func otherMouseDragged(with event: NSEvent) {
        guard isPannable else { return }
        pan(by: CGSize(width: event.deltaX, height: -event.deltaY))
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(for: imagePoint(fromView: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    // MARK: - Zoom and pan

    /// Pinch on the trackpad.
    override func magnify(with event: NSEvent) {
        guard event.magnification != 0 else { return }
        let anchor = convert(event.locationInWindow, from: nil)
        setVisualScale(model.visualScale * (1 + event.magnification), anchor: anchor)
    }

    /// Double-tap with two fingers toggles between fitting and actual size.
    override func smartMagnify(with event: NSEvent) {
        let anchor = convert(event.locationInWindow, from: nil)
        if model.zoomMode == .fit {
            setVisualScale(1, anchor: anchor)
        } else {
            model.zoomToFit()
            panOffset = .zero
            needsDisplay = true
        }
    }

    /// Two-finger scroll pans; holding ⌘ or ⌥ zooms instead.
    override func scrollWheel(with event: NSEvent) {
        let zooming = !event.modifierFlags.intersection([.command, .option]).isEmpty
        if zooming {
            let steps = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 90
                                                        : event.scrollingDeltaY / 6
            guard steps != 0 else { return }
            let anchor = convert(event.locationInWindow, from: nil)
            setVisualScale(model.visualScale * (1 + steps), anchor: anchor)
            return
        }

        guard isPannable else {
            super.scrollWheel(with: event)
            return
        }
        // Natural scrolling already matches "content follows your fingers".
        pan(by: CGSize(width: event.scrollingDeltaX, height: -event.scrollingDeltaY))
    }

    // MARK: - Interaction helpers

    private var currentColor: RGBAColor {
        model.tool == .highlighter ? model.color.withAlpha(0.4) : model.color
    }

    /// Applies shift-constraints while drawing: squares for rectangles, 45°
    /// increments for lines and arrows.
    private func constrained(_ point: CGPoint, from origin: CGPoint, shift: Bool, tool: ToolKind) -> CGPoint {
        guard shift else { return point }
        if tool.isSegmentBased {
            let dx = point.x - origin.x
            let dy = point.y - origin.y
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let length = hypot(dx, dy)
            return CGPoint(x: origin.x + cos(angle) * length, y: origin.y + sin(angle) * length)
        }
        let side = max(abs(point.x - origin.x), abs(point.y - origin.y))
        return CGPoint(x: origin.x + (point.x < origin.x ? -side : side),
                       y: origin.y + (point.y < origin.y ? -side : side))
    }

    private func beginSelectionInteraction(at point: CGPoint, clickCount: Int) {
        if let selected = model.selectedAnnotation,
           let handle = AnnotationHitTesting.handle(at: point, for: selected, tolerance: tolerance) {
            interaction = .resizing(original: selected, handle: handle, originalBounds: selected.displayBounds)
            return
        }

        guard let hit = AnnotationHitTesting.annotation(at: point, in: model.document.annotations, tolerance: tolerance) else {
            model.selectedID = nil
            interaction = .none
            return
        }

        model.selectedID = hit.id
        model.adoptStyle(from: hit)
        if clickCount >= 2, hit.tool == .text {
            beginTextEditing(for: hit)
        } else {
            interaction = .moving(original: hit, grabPoint: point)
        }
    }

    private func commitDrawn(_ annotation: Annotation) {
        var finished = annotation
        if finished.tool.isPathBased {
            guard finished.points.count > 1 else { return }
        } else {
            let bounds = CGRect(corner: finished.start, opposite: finished.end)
            let minimumSide: CGFloat = finished.tool.isSegmentBased ? 6 : 8
            guard max(bounds.width, bounds.height) >= minimumSide / max(zoom, 0.05) else { return }
            finished.points = [finished.start, finished.end]
        }
        model.addAnnotation(finished)
    }

    private func updateCursor(for point: CGPoint) {
        if textEditor != nil {
            NSCursor.iBeam.set()
            return
        }
        switch model.tool {
        case .select:
            if let selected = model.selectedAnnotation,
               let handle = AnnotationHitTesting.handle(at: point, for: selected, tolerance: tolerance) {
                cursor(for: handle.cursorKind).set()
            } else if AnnotationHitTesting.annotation(at: point, in: model.document.annotations, tolerance: tolerance) != nil {
                NSCursor.openHand.set()
            } else {
                NSCursor.arrow.set()
            }
        case .text:
            NSCursor.iBeam.set()
        default:
            NSCursor.crosshair.set()
        }
    }

    private func cursor(for kind: ResizeHandle.CursorKind) -> NSCursor {
        switch kind {
        case .horizontal: return .resizeLeftRight
        case .vertical: return .resizeUpDown
        case .diagonalDown, .diagonalUp: return .crosshair
        case .crosshair: return .crosshair
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1

        switch Int(event.keyCode) {
        case 51, 117: // Delete / Forward delete
            model.deleteSelection()
            needsDisplay = true
            return
        case 53: // Escape
            if model.tool == .crop {
                model.applyCrop(nil)
            } else {
                model.selectedID = nil
            }
            needsDisplay = true
            return
        case 123, 124, 125, 126: // Arrow keys
            nudgeSelection(keyCode: Int(event.keyCode), step: step)
            return
        default:
            break
        }

        // Tool letters are handled by the window controller's key monitor, so
        // they keep working while a toolbar control has focus.
        super.keyDown(with: event)
    }

    private func nudgeSelection(keyCode: Int, step: CGFloat) {
        guard let annotation = model.selectedAnnotation else { return }
        let delta: CGVector
        switch keyCode {
        case 123: delta = CGVector(dx: -step, dy: 0)
        case 124: delta = CGVector(dx: step, dy: 0)
        case 125: delta = CGVector(dx: 0, dy: step)
        default: delta = CGVector(dx: 0, dy: -step)
        }
        let moved = annotation.translated(dx: delta.dx, dy: delta.dy)
        // Holding an arrow key produces one undo step, not one per repeat.
        model.mutate(coalescing: "nudge-\(annotation.id)") { document in
            guard let index = document.index(of: moved.id) else { return }
            document.annotations[index] = moved
        }
        needsDisplay = true
    }

    // MARK: - Inline text editing

    private func createTextAnnotation(at point: CGPoint) {
        let annotation = Annotation(tool: .text,
                                    points: [point],
                                    color: model.color,
                                    lineWidth: model.lineWidth,
                                    fontSize: model.fontSize)
        model.addAnnotation(annotation)
        beginTextEditing(for: annotation)
    }

    func beginTextEditing(for annotation: Annotation) {
        endTextEditing(commit: true)

        let box = viewRect(fromImage: annotation.rawBounds)
        let frame = CGRect(x: box.minX, y: box.minY,
                           width: max(box.width, 140), height: max(box.height, 26))

        let editor = NSTextView(frame: frame)
        editor.delegate = self
        editor.isRichText = false
        editor.font = TextLayout.font(ofSize: annotation.fontSize * zoom)
        editor.textColor = annotation.color.nsColor
        editor.insertionPointColor = annotation.color.nsColor
        editor.drawsBackground = true
        editor.backgroundColor = NSColor.black.withAlphaComponent(0.28)
        editor.textContainerInset = NSSize(width: TextLayout.padding * zoom, height: TextLayout.padding * zoom)
        editor.string = annotation.text
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = true
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                     height: CGFloat.greatestFiniteMagnitude)

        addSubview(editor)
        textEditor = editor
        editingAnnotationID = annotation.id
        window?.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: annotation.text.count, length: 0))
        needsDisplay = true
    }

    /// Ends inline editing. Empty text removes the annotation again so a stray
    /// click never leaves an invisible object behind.
    func endTextEditing(commit: Bool) {
        guard let editor = textEditor, let id = editingAnnotationID else { return }
        let text = editor.string.trimmingCharacters(in: .whitespacesAndNewlines)

        editor.delegate = nil
        editor.removeFromSuperview()
        textEditor = nil
        editingAnnotationID = nil

        if let annotation = model.document.annotation(withID: id) {
            if !commit || text.isEmpty {
                model.deleteAnnotation(id: id)
            } else if annotation.text != editor.string {
                var updated = annotation
                updated.text = editor.string
                model.replaceAnnotation(updated)
            }
        }
        if window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
        needsDisplay = true
    }

    var isEditingText: Bool { textEditor != nil }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        guard let editor = textEditor else { return }
        // Grow the editor with the text so it always shows the full string.
        let measured = (editor.string as NSString).size(withAttributes: [.font: editor.font ?? NSFont.systemFont(ofSize: 12)])
        let lines = max(1, editor.string.components(separatedBy: .newlines).count)
        let lineHeight = (editor.font?.boundingRectForFont.height ?? 16) * CGFloat(lines)
        editor.setFrameSize(NSSize(width: max(140, measured.width + 32),
                                   height: max(26, lineHeight + TextLayout.padding * zoom * 2 + 6)))
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            endTextEditing(commit: true)
            return true
        case #selector(NSResponder.insertLineBreak(_:)):
            textView.insertText("\n", replacementRange: textView.selectedRange())
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            endTextEditing(commit: true)
            return true
        default:
            return false
        }
    }
}
