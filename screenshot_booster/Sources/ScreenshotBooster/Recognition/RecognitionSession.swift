import AppKit
import Combine

/// A single immutable image snapshot; closing its window discards the results.
@MainActor
final class RecognitionSession: ObservableObject, Identifiable {
    let id = UUID()
    private let image: CGImage
    @Published private(set) var isRunning = true
    @Published private(set) var result: RecognitionResult?
    @Published private(set) var errorMessage: String?
    @Published var text = ""
    @Published private(set) var actionMessage: String?

    init(image: CGImage) {
        self.image = image
    }

    func run() async {
        guard result == nil && errorMessage == nil else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            let output = try await RecognitionService.recognize(image)
            try Task.checkCancellation()
            result = output
            text = output.textLines.joined(separator: "\n")
        } catch is CancellationError {
            // The window has closed; nothing should be presented or copied.
        } catch {
            errorMessage = "Recognition failed: \(error.localizedDescription)"
        }
    }

    var combinedText: String {
        ([text] + (result?.qrValues ?? []))
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    func copy(_ value: String) {
        guard !value.isEmpty else { return }
        actionMessage = PasteboardService.copy(text: value)
            ? "Copied to clipboard" : "Could not copy to clipboard"
    }

    var links: [URL] { RecognitionLinks.webURLs(in: combinedText) }

    func openLink(_ url: URL) {
        guard RecognitionLinks.isWebURL(url) else { return }
        actionMessage = NSWorkspace.shared.open(url) ? nil : "Could not open the link in your browser"
    }
}
