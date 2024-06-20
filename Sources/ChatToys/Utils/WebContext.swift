import Foundation

public struct WebContext: Equatable, Codable {
    public struct Page: Equatable, Codable {
        public var searchResult: WebSearchResult
        public var markdown: String

        public init(searchResult: WebSearchResult, markdown: String) {
            self.searchResult = searchResult
            self.markdown = markdown
        }

        public var markdownWithSnippetAndTitle: String {
            var lines = [String]()
            lines.append("# " + searchResult.title)
            if let snippet = searchResult.snippet {
                lines.append(snippet)
            }

            lines.append(markdown)
            return lines.joined(separator: "\n")
        }

        public var markdownWithNodeIds: String {
            return MarkdownProcessor.markdownWithInlineNodeIds(markdown: markdown, url: searchResult.url.absoluteString)
        }
    }
    public var pages: [Page]
    public var urlMode: FastHTMLProcessor.URLMode
    public var query: String

    public var asString: String {
        var lines = [String]()
        for page in pages {
            if let processed = urlMode.process(url: page.searchResult.url) {
                lines.append("BEGIN WEB PAGE \(processed)")
            } else {
                lines.append("BEGIN WEB PAGE \(page.searchResult.url.hostWithoutWWW)")
            }
            lines.append(page.markdownWithSnippetAndTitle)

            lines.append("END WEB PAGE")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // For anthropic models, which are trained to expect xml for organizating text
    public var asXML: String {
        var lines = [String]()
        lines.append("<search-results query='\(query)'>")
        for page in pages {
            let pageTitleURLMode = FastHTMLProcessor.URLMode.truncate(200)
            if let processed = pageTitleURLMode.process(url: page.searchResult.url) {
                lines.append("<webpage url='\(processed)'>")
            } else {
                lines.append("<webpage domain='\(page.searchResult.url.hostWithoutWWW)'>")
            }
            lines.append(page.markdownWithNodeIds)

            lines.append("</webpage>")
            lines.append("")
        }
        lines.append("</search-results>")
        return lines.joined(separator: "\n")
    }

    public init(pages: [Page], urlMode: FastHTMLProcessor.URLMode, query: String) {
        self.pages = pages
        self.urlMode = urlMode
        self.query = query
    }

    public static var stub: Self {
        let count = 6
        let pages = (0..<count).map { i in
            var result = WebSearchResult.stub(id: i)
            result.url = URL(string: "https://youtube.com/\(i)")!
            return WebContext.Page(searchResult: result, markdown: "# Hello, world\nThis is the page content.")
        }
        return WebContext(pages: pages, urlMode: .keep, query: "example query")
    }
}

extension WebContext.Page {
    public static func fetch(forSearchResult result: WebSearchResult, timeout: TimeInterval, urlMode: FastHTMLProcessor.URLMode = .keep) async throws -> WebContext.Page {
        let domain = result.url.hostWithoutWWW

        if domain == "reddit.com" {
            return try await fetchRedditContent(forSearchResult: result, timeout: timeout, urlMode: urlMode)
        }

        return try await fetchNormally(forSearchResult: result, timeout: timeout, urlMode: urlMode)
    }

    static func fetchNormally(forSearchResult result: WebSearchResult, timeout: TimeInterval, urlMode: FastHTMLProcessor.URLMode) async throws -> WebContext.Page {
        try await withTimeout(timeout) {
            let resp = try await URLSession.shared.data(from: result.url)
            let proc = try FastHTMLProcessor(url: resp.1.url ?? result.url, data: resp.0)
            let markdown = proc.markdown(urlMode: urlMode)
            return .init(searchResult: result, markdown: markdown)
        }
    }

    static func fromHTML(result: WebSearchResult, html: String, urlMode: FastHTMLProcessor.URLMode) throws -> WebContext.Page {
        let proc = try FastHTMLProcessor(url: result.url, data: html.data(using: .utf8)!)
        let markdown = proc.markdown(urlMode: urlMode)
        return .init(searchResult: result, markdown: markdown)
    }
}

public extension WebContext {
    static func from(
        results: [WebSearchResult],
        query: String,
        timeout: TimeInterval,
        resultCount: Int,
        charLimit: Int,
        urlMode: FastHTMLProcessor.URLMode = .keep
    ) async throws -> WebContext {
        // TODO: Rank
        let blockedDomains = Set(["youtube.com", "twitter.com", "facebook.com", "instagram.com"])
        let elevatedDomains = Set(["en.wikipedia.org"]) // TODO: non-en
        var fetchableResults = results.filter { !blockedDomains.contains($0.url.hostWithoutWWW) }
        fetchableResults = fetchableResults.moveMatchingItemsToBeginning { elevatedDomains.contains($0.url.hostWithoutWWW) }

        let pages: [Page] = await fetchableResults.prefix(resultCount).concurrentMap { result -> Page? in
//            let idx = fetchableResults.firstIndex(of: result)!
            let pageOpt = try? await withTimeout(timeout, work: {
                // We will further limit chars later
                try? await Page.fetch(forSearchResult: result, timeout: timeout, urlMode: urlMode)
            })
            if let page = pageOpt, page.markdown.nilIfEmptyOrJustWhitespace != nil, page.markdown.count >= 20 {
                return page
            }
            return nil
        }.compactMap { $0 }

        return WebContext(pages: pages, urlMode: urlMode, query: query).trimToFit(charLimit: charLimit)
    }

    func trimToFit(charLimit: Int) -> WebContext {
        let curSum = pages.map { $0.markdown.count }.sum
        if curSum < charLimit {
            return self
        }
        let curLengthWeights = pages.map { Double($0.markdown.count) }.normalized
        let totalReduction = Double(curSum - charLimit)
        let pages: [Page] = zip(pages, curLengthWeights).map { pair in
            var (page, lengthWeight) = pair
            let reduction = lengthWeight * totalReduction
            page.markdown = page.markdown.truncateWithEllipsis(charCount: page.markdown.count - Int(reduction))
            return page
        }
        return .init(pages: pages, urlMode: urlMode, query: query)
    }
}

extension Array where Element == Int {
    var sum: Int { reduce(0, { $0 + $1 }) }
}

extension Array where Element == Double {
    var sum: Double { reduce(0.0, { $0 + $1 }) }

    var normalized: [Double] {
        let s = sum
        if s == 0 { return self }
        return map { $0 / s }
    }
}

extension String {
    func truncateWithEllipsis(charCount: Int) -> String {
        if charCount == 0 { return "" }
        if count + 1 > charCount {
            return String(prefix(charCount - 1)) + "…"
        }
        return self
    }
}

extension URL {
    var hostWithoutWWW: String {
        var parts = (host ?? "").components(separatedBy: ".")
        if parts.first == "www" {
            parts.remove(at: 0)
        }
        return parts.joined(separator: ".")
    }
}

extension Array {
    mutating func moveMatchingItemsToBeginning(_ predicate: (Element) -> Bool) -> [Element] {
        let front = filter(predicate)
        let back = filter { !predicate($0) }
        return front + back
    }
}

public class MarkdownProcessor {
    
    public static var stringToKeyMap = [String: String]()
    public static var uuidToURLMap = [String: String]()

    public static func key(for value: String) -> String? {
        return stringToKeyMap.first { $0.value == value }?.key
    }

    public static func url(for value: String) -> URL? {
        guard let textContent = key(for: value)?.nilIfEmptyOrJustWhitespace,
              var urlString = uuidToURLMap[value] else {
            return nil
        }
        
        let words = textContent.split(separator: " ")
        
        // TODO see if a more robust implementation would be warranted
        if let range = urlString.range(of: "#:~:text=") {
            let urlString = urlString[..<range.lowerBound]
        }
        
        if words.count <= 8 {
            urlString = "\(urlString)#:~:text=\( processWords(words.prefix(8)) )"
        } else {
            let start = processWords(words.prefix(4))
            let end = processWords(words.suffix(4))
            urlString = "\(urlString)#:~:text=\(start),\(end)"
        }
        
        return URL(string: urlString)
    }

    private static func processWords(_ words: ArraySlice<Substring>) -> String {
        return words.joined(separator: " ")
            .replacingOccurrences(of: ",", with: "%2C")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .trimmingCharacters(in: .whitespaces)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    }

    public static func shortUUID(_ string: String) -> String {
        if let existingKey = stringToKeyMap[string] {
            return existingKey
        }
        var uuid: String
        repeat {
            uuid = String(UUID().uuidString.prefix(4))
        } while stringToKeyMap.values.contains(uuid)
        stringToKeyMap[string] = uuid
        return uuid
    }

    public static func markdownWithInlineNodeIds(markdown: String, url: String) -> String {
        return markdown.split(separator: "\n").map { line in
            let key = shortUUID(String(line))
            uuidToURLMap[key] = url
            return "[↗](\(key)) \(line)"
        }.joined(separator: "\n")
    }
}
