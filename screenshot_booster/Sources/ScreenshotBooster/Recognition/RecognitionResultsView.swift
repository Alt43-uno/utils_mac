import SwiftUI

struct RecognitionResultsView: View {
    @ObservedObject var session: RecognitionSession
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Recognize Text & QR Codes", systemImage: "text.viewfinder")
                .font(.title2.bold())
            Text("Text and QR codes from the current screenshot, including crop and edits. Processed on your Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)

            content.frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                if let message = session.actionMessage {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(session.isRunning ? "Cancel" : "Done") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Copy All") { session.copy(session.combinedText) }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.isRunning || session.combinedText.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 400)
        .task { await session.run() }
    }

    @ViewBuilder
    private var content: some View {
        if session.isRunning {
            ProgressView("Recognizing text and QR codes…")
        } else if let error = session.errorMessage {
            message("Could not recognize this screenshot", detail: error, symbol: "exclamationmark.triangle")
        } else if let result = session.result {
            if result.isEmpty {
                message("No text or QR codes found",
                        detail: "Try a clearer screenshot or crop to the area you want to recognize.",
                        symbol: "text.viewfinder")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !result.textLines.isEmpty {
                            textSection
                        }
                        ForEach(Array(result.qrValues.enumerated()), id: \.offset) { index, value in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("QR code \(index + 1)", systemImage: "qrcode")
                                        .font(.headline)
                                    Spacer()
                                    Button("Copy") { session.copy(value) }.disabled(value.isEmpty)
                                }
                                Text(verbatim: value.isEmpty ? "Empty payload" : value)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                        }
                        if !session.links.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Links", systemImage: "link").font(.headline)
                                ForEach(session.links, id: \.absoluteString) { url in
                                    HStack(alignment: .top) {
                                        Text(verbatim: url.absoluteString)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Button("Open Link") { session.openLink(url) }
                                            .help("Open in your default browser")
                                    }
                                }
                            }
                        }
                        if result.unreadableQRCodeCount > 0 {
                            Text("\(result.unreadableQRCodeCount) QR code(s) detected without a readable text payload.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Text", systemImage: "text.alignleft").font(.headline)
                Spacer()
                Button("Copy Text") { session.copy(session.text) }.disabled(session.text.isEmpty)
            }
            TextEditor(text: $session.text)
                .font(.system(size: 14))
                .frame(height: 160)
                .padding(8)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                .accessibilityLabel("Recognized text")
        }
    }

    private func message(_ title: String, detail: String, symbol: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }
}
