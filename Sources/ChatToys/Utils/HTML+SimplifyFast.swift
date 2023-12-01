import Foundation
import Fuzi

public class FastHTMLProcessor {
    public enum URLMode {
        case omit
        case shorten(prefix: String?)
        case keep
        case truncate(Int)
    }

    let doc: HTMLDocument
    let baseURL: URL

    public init(url: URL, data: Data) throws {
        self.doc = try HTMLDocument(data: data)
        self.baseURL = url
    }

    struct MarkdownDoc {
        var bestLines = [String]()
        var normalLines = [String]()
        var worstLines = [String]()

        mutating func startNewLine(with score: Score) {
            switch score {
            case .best: bestLines.append("")
            case .normal: normalLines.append("")
            case .worst: worstLines.append("")
            }
        }
        mutating func appendInline(text: String, with score: Score) {
            switch score {
            case .best:
                bestLines.appendStringToLastItem(text)
            case .normal:
                normalLines.appendStringToLastItem(text)
            case .worst:
                worstLines.appendStringToLastItem(text)
            }
        }
        var asMarkdown: String {
            let allLines = bestLines + normalLines + worstLines
            let lines = allLines
                .compactMap { $0.nilIfEmptyOrJustWhitespace }
                .map { $0.trimmingCharacters(in: .whitespaces) }
            return lines.joined(separator: "\n").replacingOccurrences(of: FastHTMLProcessor.uncollapsedLinebreakToken, with: "\n")
        }
    }

    enum Score: Equatable {
        case best
        case normal
        case worst
    }

    public func markdown(urlMode: URLMode) -> String {
        // Steps:
        // 1. Identify target content elements to move to front
        // 2. Identify skip elements
        // 3. Traverse tree
        guard let body = doc.body else {
            return ""
        }
        var doc = MarkdownDoc()
        let mainEl: Fuzi.XMLElement = {
            for sel in ["article", "main", "#content", "[itemprop='mainEntity']"] {
                if let el = body.firstChild(css: sel) {
                    return el
                }
            }
            return body
        }()
        traverse(element: mainEl, doc: &doc, score: .normal, urlMode: urlMode)
        return doc.asMarkdown
    }

    private func traverse(element: Fuzi.XMLElement, doc: inout MarkdownDoc, score parentScore: Score, urlMode: URLMode) {
        guard var score = self.score(element: element) else {
            return // skipped
        }
        if score == .normal {
            score = parentScore // inherit
        }
        let tagLower = element.tag?.lowercased() ?? ""

        // Handle images:
        if tagLower == "img" {
            if let alt = element.attr("alt")?.nilIfEmpty, let src = element.attr("src")?.nilIfEmpty {
                doc.startNewLine(with: score)
                doc.appendInline(text: "![\(alt.collapseWhitespace)]", with: score)
                if let urlStr = processURL(src, urlMode: urlMode) {
                    doc.appendInline(text: "(\(urlStr))", with: score)
                }
                doc.startNewLine(with: score)
            }
            return
        }

        let rule: Rule? = markdownRules[tagLower]
        if let rule, !rule.inline {
            doc.startNewLine(with: score)
        }
        if let prefix = rule?.prefix {
            doc.appendInline(text: prefix, with: score)
        }
        let childNodes = element.childNodes(ofTypes: [.Text, .Element])
        for (i, node) in childNodes.enumerated() {
            let isFirst = i == 0
            let isLast = i == childNodes.count - 1
            switch node.type {
            case .Text:
                var text: any StringProtocol = node.stringValue.collapseWhitespaceWithoutTrimming
                if isFirst {
                    text = text.leadingSpacesTrimmed
                }
                if isLast {
                    text = text.trailingSpacesTrimmed
                }
                doc.appendInline(text: String(text), with: score)
            case .Element:
                if let el = node as? Fuzi.XMLElement {
                    traverse(element: el, doc: &doc, score: score, urlMode: urlMode)
                }
            default: ()
            }
        }
        if let suffix = rule?.suffix {
            doc.appendInline(text: suffix, with: score)
        }
        if tagLower == "a", let href = element.attr("href"), let processed = processURL(href, urlMode: urlMode) {
            doc.appendInline(text: "(\(processed))", with: score)
        }
        if let rule, !rule.inline {
            doc.startNewLine(with: score)
        }
    }

    private func processURL(_ raw: String, urlMode: URLMode) -> String? {
        if let url = URL(string: raw, relativeTo: baseURL), !["http", "https"].contains(url.scheme ?? "") {
            return nil
        }
        switch urlMode {
        case .keep: return raw
        case .omit: return nil
        case .truncate(let limit): return raw.truncateTail(maxLen: limit)
        case .shorten(let prefix):
            if let url = URL(string: raw, relativeTo: baseURL) {
                return shortenURL(url, prefix: prefix)
            }
            return nil
        }
    }

    // if nil, skip
    private func score(element: Fuzi.XMLElement) -> Score? {
        let tag = element.tag
        if tagsToSkip.contains(tag ?? "") {
            return nil
        }
        if element.attr("aria-hidden") == "true" {
            return nil
        }
        let role = element.attr("aria-role")
        let droppedAriaRoles = Set<String>([ "banner", "alert", "dialog", "navigation" ])
        if droppedAriaRoles.contains(role ?? "") {
            return nil
        }
        if tag == "article" || tag == "main" || element.attr("itemprop") == "mainEntity" || element.attr("id") == "content" || element.attr("class") == "reviews-content" {
            return .best
        }
        return .normal
    }
    
    private let tagsToSkip = Set<String>([
        "script",
        "style",
        "svg",
        "link",
        "footer",
        "header",
        "form",
        "option",
        "nav",
        "object",
        "iframe",
        "dialog",
    ])

    private struct Rule {
        var inline: Bool
        var prefix: String?
        var suffix: String?
        var establishesInlineContext: Bool? // https://developer.mozilla.org/en-US/docs/Web/API/Document_Object_Model/Whitespace
    }
    private static let uncollapsedLinebreakToken = UUID().uuidString
    private var markdownRules: [String: Rule] = {
        let rules: [String: Rule] = [
            "h1": Rule(inline: false, prefix: "# "),
            "h2": Rule(inline: false, prefix: "## "),
            "h3": Rule(inline: false, prefix: "### "),
            "h4": Rule(inline: false, prefix: "#### "),
            "h5": Rule(inline: false, prefix: "##### "),
            "h6": Rule(inline: false, prefix: "###### "),
            "em": Rule(inline: true, prefix: "_", suffix: "_"),
            "i": Rule(inline: true, prefix: "_", suffix: "_"),
            "q": Rule(inline: true, prefix: "\"", suffix: "\""),
            "strong": Rule(inline: true, prefix: "**", suffix: "**"),
            "a": Rule(inline: true, prefix: "[", suffix: "]"),
            "br": Rule(inline: true, suffix: FastHTMLProcessor.uncollapsedLinebreakToken),
            "p": Rule(inline: false),
            "li": Rule(inline: false, prefix: "- "),
            "blockquote": Rule(inline: false, prefix: "> "),
            "code": Rule(inline: true, prefix: "`", suffix: "`"),
            "pre": Rule(inline: false),
            "hr": Rule(inline: false, suffix: "----"),
            "caption": Rule(inline: false, suffix: "----"),
            "tr": Rule(inline: false, prefix: "| "),
            "td": Rule(inline: true, suffix: " |"),
            "div": Rule(inline: false),
        ]
        return rules
    }()

    // MARK: - Shortening

    private var longToShortURLs = [URL: String]()
    public var shortToLongURLs = [String: URL]()
    private var shortURLCountsForDomains = [String: Int]()

    private func shortenURL(_ url: URL, prefix: String? = nil) -> String {
        if let short = longToShortURLs[url] {
            return short
        } else if var host = url.host {
            host = host.withoutPrefix("www.")
            let count = shortURLCountsForDomains[host, default: 0] + 1
            let short = prefix != nil ? "\(host)/\(prefix!)/\(count)" : "\(host)/\(count)"
            shortURLCountsForDomains[host] = count
            longToShortURLs[url] = short
            shortToLongURLs[short] = url
            return short
        } else {
            return url.absoluteString
        }
    }
}

private extension Array where Element == String {
    mutating func appendStringToLastItem(_ str: String) {
        if count > 0 {
            self[count - 1].append(str)
        } else {
            self.append(str)
        }
    }
}

extension StringProtocol {
    var trailingSpacesTrimmed: Self.SubSequence {
        var view = self[...]
        while view.last?.isWhitespace == true {
            view = view.dropLast()
        }
        return view
    }
    var leadingSpacesTrimmed: Self.SubSequence {
        var view = self[...]
        while view.first?.isWhitespace == true {
            view = view.dropFirst()
        }
        return view
    }
    var replaceNewlinesAndTabsWithSpaces: String {
        components(separatedBy: .whitespacesAndNewlines)
            .joined(separator: " ")
    }

}

public extension FastHTMLProcessor {
    static func printSamples() {
        let samples: [String] = [
            "<h1>Hello world</h1>",
            """
            <h1>   Hello
                    <span> World!</span>   </h1>
            """,
            "<h1>hello</h1><p>This text is <em>emphasized</em> and <strong>bolded.</strong></p>",
            "<h2><a href=\"https://www.google.com\">WHy dont you visit <em>google?</em></a></h2>",
            "<table><tr><td>hello</td><td>world</td></tr><tr><td>goodnight</td><td>moon</td></tr></table>",
            "<img src='https://google.com/favicon.ico' alt='Google favicon' />",
            """
            <h1>
                Whitespace sample
            </h1>
            <p>
                So, this is some code:
                <code>
                    1 + 3 + 5
                </code>
                I hope you like it!
            </p>
            """
        ]
        for sample in samples {
            print("SAMPLE:\n\(sample)")
            let processor = try! FastHTMLProcessor(url: URL(string: "https://example.com")!, data: sample.data(using: .utf8)!)
            print("MARKDOWN:\n\(processor.markdown(urlMode: .keep))")
        }
    }
}
