import Foundation

enum RecognitionLinks {
    static func isWebURL(_ url: URL) -> Bool {
        ["https", "http"].contains(url.scheme?.lowercased() ?? "") && !(url.host ?? "").isEmpty
    }

    static func webURLs(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        var seen = Set<String>()
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let url = match.url, isWebURL(url), seen.insert(url.absoluteString).inserted else { return nil }
            return url
        }
    }
}
