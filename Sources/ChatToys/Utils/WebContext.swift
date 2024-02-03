import Foundation

public struct WebContext: Equatable, Codable {
    public struct Page: Equatable, Codable {
        public var searchResult: WebSearchResult
        public var markdown: String

        public var markdownWithSnippetAndTitle: String {
            var lines = [String]()
            lines.append("# " + searchResult.title)
            if let snippet = searchResult.snippet {
                lines.append(snippet)
            }

            lines.append(markdown)
            return lines.joined(separator: "n")
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

