import SwiftSoup
import Foundation

enum HTMLProcessorError: Error {
    case noBody
}

public class HTMLProcessor {
    let document: SwiftSoup.Document
    public let title: String?
    var body: Element
    let baseURL: URL?

    public init(html: String, baseURL: URL?) throws {
        self.document = try SwiftSoup.parse(html)
        self.baseURL = baseURL
        guard let body = document.body() else {
            throw HTMLProcessorError.noBody
        }
        self.title = try? document.title()
        self.body = body
        self.document.outputSettings().prettyPrint(pretty: false).syntax(syntax: .html)
    }

    public func simplify(truncateTextNodes: Int?) throws {
        // find <script type="application/ld+json"> and paste text at front of body in a <p>
        for el in try document.select("script[type='application/ld+json']") {
            if let text = try? el.html().nilIfEmpty {
                try body.prepend("<p></p>").children().first()?.text(text)
            }
        }

        try body.select("script, style, link, svg").remove()
        try body.select("[srcset]").removeAttr("srcset")

        // Truncute src attributes to 500 chars:
        for el in try body.select("[src]") {
            if let src = try? el.attr("src") {
                if src.count > 500 {
                    try el.attr("src", src.prefix(500) + "...")
                }
            }
        }

        if let truncateTextNodes {
            for el in try body.select("*") {
                if el.children().count == 0, let text = try? el.text() {
                    if text.count > truncateTextNodes {
                        try el.text(text.prefix(truncateTextNodes) + "...")
                    }
                }
            }
        }

        try body.select("[aria-hidden=true]").remove()
    }

    public func moveContentToFront() throws {
        let moveToEndSelectors = "nav, [aria-role=navigation], footer, header, [aria-role=banner], form, option, [arial-role=alert], [arial-role=dialog]"
        for el in try body.select(moveToEndSelectors) {
            try el.remove()
            try body.insertChildren(body.childNodeSize(), [el])
        }
        let moveToFrontSelectors = "[itemprop=mainEntity], article, #content, .reviews-content"
        for el in try body.select(moveToFrontSelectors) {
            try el.remove()
            try body.insertChildren(0, [el])
        }
    }

    public func isolateContent() throws {
        // Remove navigation
        try body.select("nav, [aria-role=navigation]").remove()
        // Remove footer
        try body.select("footer").remove()
        // Remove header
        try body.select("header").remove()
        try body.select("[aria-role=banner]").remove()
        // Remove form
        try body.select("form").remove()
        try body.select("option").remove()
        // Remove alerts
        try body.select("[arial-role=alert]").remove()
        // Remove dialogs
        try body.select("[arial-role=dialog]").remove()

        let contentSelectors = ["[itemprop=mainEntity]", "article", "#content"]
        for selector in contentSelectors {
            let matches = try body.select(selector)
            if matches.count == 1 {
                self.body = matches.first()!
                return
            }
        }
    }

    public func bodyOuterHTML() throws -> String {
        let html = try body.outerHtml()
        return html
    }

    public func convertToMarkdown_doNotUseObjectAfter(hideUrls: Bool) throws -> String {
        // Use UUID as token, then sub it for a linebreak at the end
        let linebreak = UUID().uuidString

        struct Rule {
            var prefix: String?
            var suffix: String?
        }
        let rules: [String: Rule] = [
            "h1": Rule(prefix: "\(linebreak)# ", suffix: linebreak),
            "h2": Rule(prefix: "\(linebreak)## ", suffix: linebreak),
            "h3": Rule(prefix: "\(linebreak)### ", suffix: linebreak),
            "h4": Rule(prefix: "\(linebreak)#### ", suffix: linebreak),
            "h5": Rule(prefix: "\(linebreak)##### ", suffix: linebreak),
            "h6": Rule(prefix: "\(linebreak)###### ", suffix: linebreak),
            "em": Rule(prefix: "_", suffix: "_"),
            "strong": Rule(prefix: "**", suffix: "**"),
            "br": Rule(prefix: nil, suffix: linebreak),
            "p": Rule(prefix: linebreak, suffix: linebreak),
            "li": Rule(prefix: "\(linebreak)- ", suffix: linebreak),
            "blockquote": Rule(prefix: "\(linebreak)> ", suffix: linebreak),
            "code": Rule(prefix: "``", suffix: "`"),
        ]

        try timeExecution(printWithLabel: "Rules") {
            // Apply rules
            for (tag, rule) in rules {
                for el in try body.select(tag) {
                    if let prefix = rule.prefix {
                        try el.before(prefix)
                    }
                    if let suffix = rule.suffix {
                        try el.after(suffix)
                    }
                }
            }
        }

        try timeExecution(printWithLabel: "Links") {
            // Handle links
            for el in try body.select("a") {
                if let text = try? el.text(trimAndNormaliseWhitespace: false).trimmed.nilIfEmpty {
                    if !hideUrls, let href = try? el.attr("href") {
                        try el.text("[\(text)](\(href))")
                    } else {
                        try el.text("[\(text)]")
                    }
                }
            }
        }

        // Handle images
        for el in try body.select("img") {
            // for inner text, use alt
            if let alt = try? el.attr("alt").trimmed {
                if let url = try? el.attr("src").nilIfEmpty, !hideUrls {
                    try el.prependText("![\(alt)](\(url))")
                } else {
                    try el.prependText("![\(alt)]")
                }
            }
            try el.remove()
        }

        // TODO: Keep original indentation
        for el in try body.select("pre") {
            if let text = try? el.text().nilIfEmpty {
                let textWithLinebreaks = text.components(separatedBy: "\n").joined(separator: linebreak + "    ")
                try el.text("\(linebreak)```\(linebreak)\(textWithLinebreaks)\(linebreak)```\(linebreak)")
            }
        }

        let baseText = try timeExecution(printWithLabel: "baseText", {
            try body.text(trimAndNormaliseWhitespace: false) // true)
        })

        let parts = timeExecution(printWithLabel: "Parts") {
            baseText
                .components(separatedBy: linebreak)
                .map { $0.collapseWhitespace.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ") }
                .compactMap { $0.nilIfEmpty }
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - URL Shortening

    public var shortToLongURLs: [String: URL] = [:]
    private var longToShortURLs: [URL: String] = [:]
    private var shortURLCountsForDomains = [String: Int]()

    public func shortenURLs() throws {
        // For hrefs and img srcs, shorten URLs
        for el in try body.select("a, img") {
            if let href = try? el.attr("href").nilIfEmpty {
                if let url = URL(string: href, relativeTo: baseURL) {
                    try el.attr("href", shortenURL(url))
                }
            }
            if let src = try? el.attr("src").nilIfEmpty {
                if let url = URL(string: src, relativeTo: baseURL) {
                    try el.attr("src", shortenURL(url))
                }
            }
        }
    }

    private func shortenURL(_ url: URL) -> String {
        if let short = longToShortURLs[url] {
            return short
        } else if var host = url.host {
            host = host.withoutPrefix("www.")
            let count = shortURLCountsForDomains[host, default: 0] + 1
            let short = "\(host)/\(count)"
            shortURLCountsForDomains[host] = count
            longToShortURLs[url] = short
            shortToLongURLs[short] = url
            return short
        } else {
            return url.absoluteString
        }
    }

    public func expand(url: String) -> URL? {
        shortToLongURLs[url] ?? URL(string: url)
    }

    static public func expandShortUrls(markdown text: String, urlMapping: [String: URL]) -> String {
        let pattern = #"(\b|\(|\[)([a-zA-Z0-9.-]+\.com/\d+)(\b|\)|\])"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        var mutableText = text

        func expand(url: String) -> String? {
            urlMapping[url]?.absoluteString
        }

        for match in matches.reversed() {
            if let urlRange = Range(match.range(at: 2), in: text),
               let expandedURL = expand(url: String(text[urlRange])) {
                mutableText.replaceSubrange(urlRange, with: expandedURL)
            }
        }

        return mutableText
    }
}

extension String {
    var collapseWhitespace: String {
        components(separatedBy: .whitespacesAndNewlines).filter({ $0.count > 0 }).joined(separator: " ")
    }

    public func simplifyHTML(baseURL: URL?, truncateTextNodes: Int?, contentOnly: Bool = false) -> String? {
        do {
            let proc = try HTMLProcessor(html: self, baseURL: baseURL)
            try proc.simplify(truncateTextNodes: truncateTextNodes)
            if contentOnly {
                try proc.isolateContent()
            }
            return try proc.bodyOuterHTML()
        } catch {
            return nil
        }
    }

    func withoutPrefix(_ prefix: String) -> String {
        if hasPrefix(prefix) {
            return String(dropFirst(prefix.count))
        }
        return self
    }
}

func timeExecution<T>(printWithLabel label: String?, _ block: () throws -> T) rethrows -> T {
    let start = Date()
    let result = try block()
    if let label {
        let end = Date()
        let elapsed = end.timeIntervalSince(start)
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 3
        formatter.maximumFractionDigits = 3
        formatter.minimumIntegerDigits = 1
        formatter.roundingMode = .halfUp
        let ms = formatter.string(from: NSNumber(value: elapsed * 1000))!
        print("🏁 \(label): \(ms) ms")
    }
    return result
}

