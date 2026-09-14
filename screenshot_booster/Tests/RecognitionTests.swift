import AppKit
import CoreImage.CIFilterBuiltins

@MainActor
func runRecognitionTests(_ runner: inout TestRunner) async {
    runner.section("Local text and QR recognition")
    do {
        let context = recognitionTestContext(width: 1100, height: 400)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black
        ]
        ("Screenshot Booster 12345" as NSString).draw(at: CGPoint(x: 50, y: 270), withAttributes: attributes)
        ("Привет мир" as NSString).draw(at: CGPoint(x: 50, y: 170), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        let textImage = context.makeImage()!
        let textResult = try await RecognitionService.recognize(textImage)
        let text = textResult.textLines.joined(separator: "\n")
        runner.expect(text.contains("Screenshot Booster 12345"), "extracts English text and digits")
        runner.expect(text.lowercased().contains("привет мир"), "extracts Cyrillic text in a mixed-language image")
        runner.expect(text.hasPrefix("Screenshot"), "keeps the top line first")
        runner.expect(text.contains("\n"), "preserves separate text lines")

        let blank = recognitionTestContext(width: 800, height: 600).makeImage()!
        let emptyText = try await RecognitionService.recognize(blank)
        runner.expect(emptyText.isEmpty,
                      "blank images return empty results for both text and QR codes")

        let payloads = ["https://example.com/qr?value=123", "WIFI:T:WPA;S:Test Network;P:example123;;"]
        let qrContext = recognitionTestContext(width: 1100, height: 600)
        qrContext.interpolationQuality = .none
        for (index, payload) in payloads.enumerated() {
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(payload.utf8)
            filter.correctionLevel = "M"
            let code = filter.outputImage!
            let bitmap = CIContext().createCGImage(code, from: code.extent)!
            qrContext.draw(bitmap, in: CGRect(x: 60 + index * 550, y: 120, width: 360, height: 360))
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: qrContext, flipped: false)
        ("Combined recognition 67890" as NSString).draw(at: CGPoint(x: 50, y: 520), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        let qrImage = qrContext.makeImage()!
        let qrResult = try await RecognitionService.recognize(qrImage)
        runner.expect(qrResult.qrValues.count == 2 && Set(qrResult.qrValues) == Set(payloads),
                      "decodes multiple QR codes and preserves URL and Wi-Fi payloads exactly")
        runner.expect(qrResult.textLines.joined(separator: " ").contains("Combined recognition 67890"),
                      "a single recognition request extracts text alongside both QR codes")
        runner.expect(qrResult.unreadableQRCodeCount == 0, "decoded QR codes are not reported as unreadable")

        let settings = TestFixtures.makeSettings(suite: "com.screenshotbooster.tests.recognition")
        let library = ScreenshotLibrary(settings: settings)
        let screenshot = Screenshot(fileName: "recognition-test.png", pixelWidth: qrImage.width,
                                    pixelHeight: qrImage.height, scale: 2, mode: .area)
        let document = ScreenshotDocument(base: qrImage,
                                          cropRect: CGRect(x: 0, y: 0, width: 520, height: 600), scale: 2)
        let model = EditorViewModel(screenshot: screenshot, document: document, library: library, settings: settings)
        var deliveredImage: CGImage?
        model.onRecognize = { deliveredImage = $0 }
        model.recognize()
        let session = RecognitionSession(image: deliveredImage!)
        await session.run()
        runner.expect(session.result?.qrValues == [payloads[0]],
                      "editor recognition respects the current crop at Retina scale")
        runner.expect(!session.isRunning && session.errorMessage == nil && session.combinedText.contains(payloads[0]),
                      "result session finishes with copyable QR contents")
        session.text = "Corrected text"
        runner.expect(session.combinedText == "Corrected text\n\n" + payloads[0],
                      "Copy All combines corrected text with the decoded QR payload")
        runner.expect(session.links.map(\.absoluteString) == [payloads[0]],
                      "decoded web links are available to open in the browser")
        let stored = try library.add(image: qrImage, scale: 2, mode: .area, sourceName: nil)
        var thumbnailImage: CGImage?
        let editors = EditorWindowManager(library: library, settings: settings) { thumbnailImage = $0 }
        editors.recognize(stored)
        runner.expect(thumbnailImage != nil && !editors.hasOpenEditors,
                      "thumbnail recognition delivers the image without opening a screenshot editor")
        library.remove(id: stored.id)

        let cover = Annotation(tool: .rect, points: [.zero, CGPoint(x: 1100, y: 400)],
                               color: RGBAColor(red: 1, green: 1, blue: 1, alpha: 1),
                               lineWidth: 1, isFilled: true)
        let coveredDocument = ScreenshotDocument(base: textImage, annotations: [cover], scale: 1)
        let coveredModel = EditorViewModel(screenshot: screenshot, document: coveredDocument,
                                           library: library, settings: settings)
        coveredModel.onRecognize = { deliveredImage = $0 }
        coveredModel.recognize()
        let coveredSession = RecognitionSession(image: deliveredImage!)
        await coveredSession.run()
        runner.expect(coveredSession.result?.isEmpty == true,
                      "recognition uses rendered annotations rather than text hidden underneath them")

        let links = RecognitionLinks.webURLs(in: "Visit https://example.com/one and https://example.com/one or http://example.org/two")
        runner.expect(links.map(\.absoluteString) == ["https://example.com/one", "http://example.org/two"],
                      "web links in recognized text are detected and deduplicated")
        runner.expect(!RecognitionLinks.isWebURL(URL(string: "file:///tmp/test")!) &&
                      !RecognitionLinks.isWebURL(URL(string: "javascript:alert(1)")!) &&
                      !RecognitionLinks.isWebURL(URL(string: "mailto:test@example.com")!),
                      "Open Link accepts browser web addresses only")

        let task = Task { try await RecognitionService.recognize(qrImage) }
        task.cancel()
        do {
            _ = try await task.value
            runner.expect(false, "cancelled recognition does not deliver results")
        } catch is CancellationError {
            runner.expect(true, "cancelled recognition does not deliver results")
        }
    } catch {
        runner.expect(false, "recognition completes without error: \(error.localizedDescription)")
    }
}

private func recognitionTestContext(width: Int, height: Int) -> CGContext {
    let context = ImageUtilities.makeContext(pixelWidth: width, pixelHeight: height)!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context
}
