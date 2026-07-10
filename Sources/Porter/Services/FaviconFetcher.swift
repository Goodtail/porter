import AppKit
import Foundation

/// Fetches a service's favicon from the running service itself:
/// `GET /favicon.ico`, falling back to parsing `<link rel="icon">` from the
/// homepage. Works identically for local and remote targets — any port
/// reachable enough to show an OPEN button can also serve its icon.
enum FaviconFetcher {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        return URLSession(configuration: config)
    }()

    /// Cache key for a service URL ("localhost:3000", "100.67.83.28:8081").
    static func key(_ url: URL) -> String {
        "\(url.host ?? "?"):\(url.port ?? 80)"
    }

    static func fetch(base: URL) async -> NSImage? {
        if let icon = await loadImage(url: base.appendingPathComponent("favicon.ico")) {
            return icon
        }
        guard let html = await loadText(url: base),
              let path = iconPath(fromHTML: html),
              let iconURL = URL(string: path, relativeTo: base)?.absoluteURL else {
            return nil
        }
        return await loadImage(url: iconURL)
    }

    /// First `<link rel="…icon…">` href in the document, if any.
    static func iconPath(fromHTML html: String) -> String? {
        let linkPattern = #"<link\b[^>]*>"#
        let relPattern = #"rel\s*=\s*["'][^"']*icon[^"']*["']"#
        let hrefPattern = #"href\s*=\s*["']([^"']+)["']"#
        guard let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: .caseInsensitive),
              let relRegex = try? NSRegularExpression(pattern: relPattern, options: .caseInsensitive),
              let hrefRegex = try? NSRegularExpression(pattern: hrefPattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(html.startIndex..., in: html)
        for match in linkRegex.matches(in: html, range: range) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            let tagNSRange = NSRange(tag.startIndex..., in: tag)
            guard relRegex.firstMatch(in: tag, range: tagNSRange) != nil,
                  let href = hrefRegex.firstMatch(in: tag, range: tagNSRange),
                  let hrefRange = Range(href.range(at: 1), in: tag) else { continue }
            return String(tag[hrefRange])
        }
        return nil
    }

    private static func loadImage(url: URL) async -> NSImage? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse).map({ $0.statusCode == 200 }) ?? true,
              data.count > 0, data.count < 512_000,
              let image = NSImage(data: data), image.isValid else {
            return nil
        }
        return image
    }

    private static func loadText(url: URL) async -> String? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse).map({ $0.statusCode == 200 }) ?? true else {
            return nil
        }
        return String(data: data.prefix(64_000), encoding: .utf8)
    }
}
