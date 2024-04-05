import Foundation
import Fuzi

public class FastHTMLProcessor {
    public enum URLMode: Equatable, Codable {
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

    public func markdown(urlMode: URLMode, hideImages: Bool = false) -> String {
        guard let body = doc.body else {
            return ""
        }
        var doc = MarkdownDoc()

        // First, look for special semantic JSON LD elements and move them to the front:
        prependJsonLDData(urlMode: urlMode, toDoc: &doc)

        // Then, detect main content elements and conver them to markdown:
        let mainElements: [Fuzi.XMLElement] = {
            for sel in ["article", "main", "#content", "*[itemprop='mainEntity']"] {
                let matches = body.css(sel)
                if matches.count > 0 {
                    return Array(matches)
                }
            }
            return [body]
        }()
        for el in mainElements {
            traverse(element: el, doc: &doc, score: .normal, urlMode: urlMode, withinInline: false, hideImages: hideImages)
        }
        return doc.asMarkdown
    }

    private func prependJsonLDData(urlMode: URLMode, toDoc doc: inout MarkdownDoc) {
        // First, look for JSON in script tags:
        for script in self.doc.css("script[type='application/ld+json']") {
            if let text = script.stringValue.data(using: .utf8) {
                if let json = try? JSONSerialization.jsonObject(with: text, options: []) {
                    let processed = processJsonLD(inJson: json, urlMode: urlMode)
                    if let encoded = try? JSONSerialization.data(withJSONObject: processed, options: []) {
                        if let str = String(data: encoded, encoding: .utf8) {
                            doc.bestLines.append(str)
                        }
                    }
                }
            }
        }
        // Then, look for items with [itemprop] attributes and prepend them like "key: value"
        for el in self.doc.css("*[itemprop]") {
            // Skip main entity; handle separately in HTML processing
            if let key = el.attr("itemprop"), key.lowercased() != "mainEntity" {
                if var value = el.stringValue.nilIfEmptyOrJustWhitespace ?? el.attr("content")?.nilIfEmptyOrJustWhitespace {
                    if value.isURL, let processed = processURL(value, urlMode: urlMode) {
                        value = processed
                    }
                    if value.nilIfEmptyOrJustWhitespace != nil {
                        doc.bestLines.append("\(key): \(value.collapseWhitespaceWithoutTrimming.leadingSpacesTrimmed.trailingSpacesTrimmed)")
                    }
                }
            }
        }
    }

    private func traverse(element: Fuzi.XMLElement, doc: inout MarkdownDoc, score parentScore: Score, urlMode: URLMode, withinInline: Bool, hideImages: Bool) {
        guard var score = self.score(element: element) else {
            return // skipped
        }
        if score == .normal {
            score = parentScore // inherit
        }
        let tagLower = element.tag?.lowercased() ?? ""

        // Handle images:
        if tagLower == "img" {
            if hideImages {
                return
            }
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

        var rule: Rule? = markdownRules[tagLower]
        if tagLower == "a" && urlMode == .omit {
            rule = nil // If urls are omitted, do not process `a` tags specially (but keep their inner content)
        }
        let inline = withinInline || (rule?.inline ?? false)
        if let rule, !rule.inline, !inline {
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
                    traverse(
                        element: el,
                        doc: &doc,
                        score: score,
                        urlMode: urlMode,
                        withinInline: inline,
                        hideImages: hideImages
                    )
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
        if let rule, !rule.inline, !inline {
            doc.startNewLine(with: score)
        }
    }

    private func processURL(_ raw: String, urlMode: URLMode) -> String? {
        if let url = URL(string: raw, relativeTo: baseURL), !["http", "https"].contains(url.scheme ?? "") {
            return nil
        }
        switch urlMode {
        case .shorten(let prefix):
            if let url = URL(string: raw, relativeTo: baseURL) {
                return shortenURL(url, prefix: prefix)
            }
            return nil
        case .keep, .omit, .truncate:
            if let url = URL(string: raw, relativeTo: baseURL) {
                return urlMode.process(url: url)
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
        let droppedAriaRoles = Set<String>([ "banner", "alert", "dialog", "navigation", "button" ])
        if droppedAriaRoles.contains(role ?? "") {
            return nil
        }
        let classes = (element.attr("class")?.split(separator: " ") ?? []).map { String($0) }
        if classesToSkip.intersection(classes).count > 0 {
            return nil
        }
        let style = element.attr("style") ?? ""
        if style.contains("display: none") || style.contains("display:none") {
            return nil
        }
        if tag == "article" || tag == "main" || element.attr("itemprop") == "mainEntity" || element.attr("id") == "content" || classes.contains("reviews-content") {
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
        "button",
    ])

    private let classesToSkip = Set<String>([
        "MuiFormControlLabel-root",
        "nomobile", // For wikipedia
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
            "caption": Rule(inline: false),
//            "tr": Rule(inline: false, prefix: "| "),
//            "td": Rule(inline: true, suffix: " |"),
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

extension FastHTMLProcessor.URLMode {
    func process(url: URL) -> String? {
        switch self {
        case .keep: return url.absoluteString
        case .omit: return nil
        case .truncate(let limit): return url.absoluteString.truncateTail(maxLen: limit)
        case .shorten: fatalError("Can't shorten HTMLs with this API")
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

func processJsonLD(inJson json: Any, urlMode: FastHTMLProcessor.URLMode) -> Any {
    let skipKeys = ["@type", "@context"]
    if let dict = json as? [String: Any] {
        var newDict = [String: Any]()
        for (k, v) in dict {
            let newVal = processJsonLD(inJson: v, urlMode: urlMode)
            if (newVal as? NSNull) != nil || (newVal as? String) == "" || skipKeys.contains(k) {
                // skip
            } else {
                newDict[k] = processJsonLD(inJson: v, urlMode: urlMode)
            }
        }
        return newDict
    } else if let arr = json as? [Any] {
        return arr.map { processJsonLD(inJson: $0, urlMode: urlMode) }
    } else if let str = json as? String {
        if str.isURL, let url = URL(string: str) {
            if let processed = urlMode.process(url: url) {
                return processed
            }
            return ""
        } else {
            return str
        }
    } else {
        return json
    }
}

extension String {
    var isURL: Bool {
        if starts(with: "https://") || starts(with: "http://"),
           firstIndex(where: { $0.isWhitespace }) == nil {
            return true
        }
        return false
    }
}
