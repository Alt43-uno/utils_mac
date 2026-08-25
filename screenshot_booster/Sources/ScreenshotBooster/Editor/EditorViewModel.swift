import AppKit
import Combine

/// State and commands for one open editor window.
///
/// The document is a value type, so undo/redo is a plain stack of snapshots —
/// cheap here because the (large) base bitmap is a shared reference and only the
/// annotation array is copied.
@MainActor
final class EditorViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var document: ScreenshotDocument
    @Published var tool: ToolKind = .pen {
        didSet {
            guard tool != oldValue else { return }
            if tool != .select { selectedID = nil }
        }
    }
    @Published var color: RGBAColor = .defaultAnnotation
    @Published var lineWidth: CGFloat = 4
    @Published var fontSize: CGFloat = 32
    @Published var selectedID: UUID?
    /// How the document is scaled on screen.
    @Published var zoomMode: ZoomMode = .fit
    /// Scale that fits the document in the current window, reported by the canvas.
    @Published private(set) var fitScale: CGFloat = 1
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var status: StatusMessage?

    /// `fit` follows the window; `factor` is an explicit pixels-to-points scale.
    enum ZoomMode: Equatable {
        case fit
        case factor(CGFloat)
    }

    struct StatusMessage: Equatable {
        let text: String
        let isError: Bool
        let id = UUID()

        static func == (lhs: StatusMessage, rhs: StatusMessage) -> Bool { lhs.id == rhs.id }
    }

    let effects = EffectCache()
    let screenshotID: UUID
    private(set) var screenshot: Screenshot

    private let library: ScreenshotLibrary
    private let settings: SettingsStore

    private var undoStack: [ScreenshotDocument] = []
    private var redoStack: [ScreenshotDocument] = []
    private let historyLimit = 60
    private var statusResetWorkItem: DispatchWorkItem?
    private var persistWorkItem: DispatchWorkItem?
    /// Continuous edits (a slider drag, a burst of arrow-key nudges) collapse
    /// into a single undo step instead of flooding the history.
    private var coalesceKey: String?
    private var coalesceDeadline: Date = .distantPast
    private let coalesceWindow: TimeInterval = 1.0

    /// Fired whenever the rendered result changes, so the window title and the
    /// pinned thumbnail can follow along.
    var onDocumentChanged: (() -> Void)?

    init(screenshot: Screenshot, document: ScreenshotDocument, library: ScreenshotLibrary, settings: SettingsStore) {
        self.screenshot = screenshot
        self.screenshotID = screenshot.id
        self.document = document
        self.library = library
        self.settings = settings
    }

    deinit {
        // `DispatchWorkItem.cancel()` is safe from any thread, unlike
        // `Timer.invalidate()`, which must run on the scheduling run loop.
        statusResetWorkItem?.cancel()
        persistWorkItem?.cancel()
    }

    // MARK: - Zoom

    /// Zoom steps, expressed as a multiple of the image's actual pixel size.
    private static let zoomLadder: [CGFloat] = [0.1, 0.25, 0.33, 0.5, 0.66, 1, 1.5, 2, 3, 4, 6, 8, 12, 16]

    /// Pixels-to-points factor currently in use.
    var zoomFactor: CGFloat {
        if case .factor(let factor) = zoomMode { return factor }
        return fitScale
    }

    /// 1.0 means one image pixel per screen pixel.
    var visualScale: CGFloat {
        zoomFactor * max(document.scale, 1)
    }

    var zoomPercent: Int {
        Int((visualScale * 100).rounded())
    }

    var canZoomIn: Bool { visualScale < Self.zoomLadder.last! - 0.001 }
    var canZoomOut: Bool { visualScale > Self.zoomLadder.first! + 0.001 }

    /// Called by the canvas whenever the window size changes the fit.
    func updateFitScale(_ scale: CGFloat) {
        guard abs(scale - fitScale) > 0.0001 else { return }
        fitScale = scale
    }

    func setVisualScale(_ scale: CGFloat) {
        let clamped = min(max(scale, Self.zoomLadder.first!), Self.zoomLadder.last!)
        zoomMode = .factor(clamped / max(document.scale, 1))
    }

    func zoomIn() {
        let current = visualScale
        setVisualScale(Self.zoomLadder.first { $0 > current + 0.001 } ?? Self.zoomLadder.last!)
    }

    func zoomOut() {
        let current = visualScale
        setVisualScale(Self.zoomLadder.last { $0 < current - 0.001 } ?? Self.zoomLadder.first!)
    }

    func zoomToActualSize() {
        setVisualScale(1)
    }

    func zoomToFit() {
        zoomMode = .fit
    }

    // MARK: - Derived

    var selectedAnnotation: Annotation? {
        selectedID.flatMap { id in document.annotations.first { $0.id == id } }
    }

    var outputSize: CGSize { document.outputSize }

    var titleText: String {
        let size = document.outputSize
        return "\(screenshot.displayTitle) — \(Int(size.width)) × \(Int(size.height))"
    }

    // MARK: - Mutations

    /// Applies a change and records it for undo.
    ///
    /// Passing the same `coalescing` key twice in quick succession keeps a
    /// single undo entry — used by the style sliders and arrow-key nudging.
    func mutate(coalescing key: String? = nil, _ change: (inout ScreenshotDocument) -> Void) {
        var updated = document
        change(&updated)
        guard updated != document else { return }

        let now = Date()
        let canCoalesce = key != nil && key == coalesceKey && now < coalesceDeadline && !undoStack.isEmpty
        if canCoalesce {
            redoStack.removeAll()
            refreshHistoryFlags()
        } else {
            pushUndo()
        }
        coalesceKey = key
        coalesceDeadline = now.addingTimeInterval(coalesceWindow)

        document = updated
        schedulePersist()
    }

    func addAnnotation(_ annotation: Annotation) {
        mutate { $0.annotations.append(annotation) }
        if tool == .text { selectedID = annotation.id }
    }

    func replaceAnnotation(_ annotation: Annotation) {
        mutate { document in
            guard let index = document.index(of: annotation.id) else { return }
            document.annotations[index] = annotation
        }
    }

    func deleteAnnotation(id: UUID) {
        mutate { $0.annotations.removeAll { $0.id == id } }
        if selectedID == id { selectedID = nil }
    }

    func deleteSelection() {
        guard let selectedID else { return }
        deleteAnnotation(id: selectedID)
    }

    func bringSelectionToFront() {
        guard let selectedID, let index = document.index(of: selectedID) else { return }
        mutate { document in
            let annotation = document.annotations.remove(at: index)
            document.annotations.append(annotation)
        }
    }

    /// Ends the current coalescing run so the next edit always starts a fresh
    /// undo step (called when a drag or a keyboard burst finishes).
    func endCoalescing() {
        coalesceKey = nil
        coalesceDeadline = .distantPast
    }

    func applyCrop(_ rect: CGRect?) {
        let normalised = rect.map { $0.pixelAligned.clamped(to: document.baseBounds) }
        if let normalised, normalised.width < 8 || normalised.height < 8 { return }
        mutate { $0.cropRect = normalised }
    }

    /// Applies the current colour/width to the selection, or just updates the
    /// defaults when nothing is selected.
    func applyStyleToSelection() {
        guard let annotation = selectedAnnotation else { return }
        var updated = annotation
        if annotation.tool.usesColor { updated.color = color }
        if annotation.tool.usesLineWidth { updated.lineWidth = lineWidth }
        if annotation.tool == .text { updated.fontSize = fontSize }
        guard updated != annotation else { return }
        mutate(coalescing: "style-\(annotation.id)") { document in
            guard let index = document.index(of: updated.id) else { return }
            document.annotations[index] = updated
        }
    }

    /// Loads the style controls from the selected object so editing feels direct.
    func adoptStyle(from annotation: Annotation) {
        if annotation.tool.usesColor { color = annotation.color }
        if annotation.tool.usesLineWidth { lineWidth = annotation.lineWidth }
        if annotation.tool == .text { fontSize = annotation.fontSize }
    }

    // MARK: - History

    private func pushUndo() {
        undoStack.append(document)
        if undoStack.count > historyLimit { undoStack.removeFirst() }
        redoStack.removeAll()
        refreshHistoryFlags()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        document = previous
        pruneSelection()
        endCoalescing()
        refreshHistoryFlags()
        schedulePersist()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
        pruneSelection()
        endCoalescing()
        refreshHistoryFlags()
        schedulePersist()
    }

    private func pruneSelection() {
        if let selectedID, document.index(of: selectedID) == nil {
            self.selectedID = nil
        }
    }

    private func refreshHistoryFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    // MARK: - Persistence & export

    /// Mirrors the edits back into the pinned screenshot.
    ///
    /// Debounced: each `library.update` invalidates the thumbnail, and
    /// re-rendering a full-resolution screenshot on every slider tick would make
    /// the editor crawl.
    private func schedulePersist() {
        onDocumentChanged?()
        persistWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.persistNow() }
        }
        persistWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    /// Writes the current edits back immediately — used when the window closes.
    func persistNow() {
        persistWorkItem?.cancel()
        persistWorkItem = nil
        guard screenshot.annotations != document.annotations || screenshot.cropRect != document.cropRect else { return }
        screenshot.annotations = document.annotations
        screenshot.cropRect = document.cropRect
        library.update(screenshot)
    }

    func flattenedImage() throws -> CGImage {
        guard let image = AnnotationRenderer.flatten(document, effects: effects) else {
            throw AppError.imageEncodingFailed
        }
        return image
    }

    func copyToClipboard() {
        persistNow()
        do {
            let image = try flattenedImage()
            PasteboardService.copy(image: image)
            show(status: "Copied to clipboard")
        } catch {
            report(error)
        }
    }

    /// Saves to the previously used destination, or the configured folder.
    func save() {
        persistNow()
        do {
            let image = try flattenedImage()
            if let existing = screenshot.lastSavedURL {
                let format = ImageFormat.allCases.first { $0.fileExtension == existing.pathExtension.lowercased() }
                    ?? settings.imageFormat
                try ExportService.write(image, to: existing, format: format, quality: settings.exportQuality)
                show(status: "Saved to \(existing.lastPathComponent)")
            } else {
                let url = try ExportService.saveToConfiguredFolder(image,
                                                                   date: screenshot.createdAt,
                                                                   settings: settings)
                screenshot.lastSavedPath = url.path
                library.update(screenshot)
                show(status: "Saved to \(url.lastPathComponent)")
            }
        } catch {
            report(error)
        }
    }

    func saveAs() {
        persistNow()
        do {
            let image = try flattenedImage()
            let suggested = screenshot.lastSavedURL?.lastPathComponent
                ?? AppPaths.suggestedFileName(for: screenshot.createdAt, format: settings.imageFormat)
            let directory = screenshot.lastSavedURL?.deletingLastPathComponent() ?? settings.saveDirectory
            if let url = try ExportService.runSavePanel(image: image,
                                                        suggestedName: suggested,
                                                        directory: directory,
                                                        settings: settings,
                                                        accessoryFormat: settings.imageFormat) {
                screenshot.lastSavedPath = url.path
                library.update(screenshot)
                show(status: "Saved to \(url.lastPathComponent)")
            }
        } catch {
            report(error)
        }
    }

    // MARK: - Status

    func show(status text: String, isError: Bool = false) {
        status = StatusMessage(text: text, isError: isError)
        statusResetWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.status = nil }
        }
        statusResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: workItem)
    }

    private func report(_ error: Error) {
        Log.editor.error("Editor action failed: \(error.localizedDescription, privacy: .public)")
        show(status: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription, isError: true)
    }
}
