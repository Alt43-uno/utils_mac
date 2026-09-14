import Foundation
import Vision

struct RecognitionResult: Sendable {
    var textLines: [String]
    var qrValues: [String]
    var unreadableQRCodeCount = 0

    var isEmpty: Bool { textLines.isEmpty && qrValues.isEmpty && unreadableQRCodeCount == 0 }
}

/// Both detectors receive the same rendered screenshot at full resolution.
/// Vision runs off the main actor and never sends images to a remote service.
enum RecognitionService {
    static func recognize(_ image: CGImage) async throws -> RecognitionResult {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.automaticallyDetectsLanguage = true
            textRequest.usesLanguageCorrection = true
            // Explicitly include Cyrillic alongside Latin for mixed screenshots.
            let supported = try textRequest.supportedRecognitionLanguages()
            let preferred = Locale.preferredLanguages + ["ru-RU", "en-US"]
            var languages: [String] = []
            for language in preferred {
                let prefix = language.split(separator: "-").first
                if let match = supported.first(where: { $0 == language })
                    ?? supported.first(where: { $0.split(separator: "-").first == prefix }),
                   !languages.contains(match) {
                    languages.append(match)
                }
            }
            if !languages.isEmpty { textRequest.recognitionLanguages = languages }

            let qrRequest = VNDetectBarcodesRequest()
            qrRequest.symbologies = [.qr]
            let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
            try handler.perform([textRequest, qrRequest])
            try Task.checkCancellation()

            let codes = (qrRequest.results ?? []).sorted {
                if $0.boundingBox.midY != $1.boundingBox.midY {
                    return $0.boundingBox.midY > $1.boundingBox.midY
                }
                return $0.boundingBox.minX < $1.boundingBox.minX
            }
            let qrValues = codes.compactMap(\.payloadStringValue)
            // Preserve Vision's reading order and line breaks for text.
            return RecognitionResult(
                textLines: (textRequest.results ?? []).compactMap { $0.topCandidates(1).first?.string },
                qrValues: qrValues,
                unreadableQRCodeCount: codes.count - qrValues.count
            )
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            worker.cancel()
        }
    }
}
