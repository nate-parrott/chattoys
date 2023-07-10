import Foundation
import SwiftSoup

public struct GoogleSearchEngine: WebSearchEngine {
    public init() {
    }

    // MARK: - WebSearchEngine
    public func search(query: String) async throws -> [WebSearchResult] {
        var urlComponents = URLComponents(string: "https://www.google.com/search")!
        urlComponents.queryItems = [
            URLQueryItem(name: "q", value: query),
        ]
        var request = URLRequest(url: urlComponents.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let chromeUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36"
        request.setValue(chromeUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw SearchError.invalidHTML
        }
        let baseURL = response.url ?? urlComponents.url!
        return try extract(html: html, baseURL: baseURL)
    }

    private func extract(html: String, baseURL: URL) throws -> [WebSearchResult] {
        let doc = try SwiftSoup.parse(html, baseURL.absoluteString)
        guard let main = try doc.select("#main").first() else {
            throw SearchError.missingMainElement
        }

        /*
         In the Google search result DOM tree:
         - #main contains all search results (but also some navigational stuff)
         - Results are wrapped in many layers of divs
         - Result links look like this: <a href=''>
           - They contain (several layers deep):
             - A url breadcrumbs view built out of divs
             - An h3 containing the result title
         - Result snippets can be found by:
            - Starting at the <a>
            - Going up three levels and selecting the _second_ div child
            - Finding the first child of this div that contains text, and extracting all inner text
         - Some results (e.g. youtube) may include multiple spans and <br> elements in their snippets.
         */

        var results = [WebSearchResult]()
        // Exclude role=heading; this indicates an image section
        // Exclude aria-hidden=true; this indicates the 'more results' cell
        for anchor in try main.select("a:has(h3:not([role=heading], [aria-hidden=true]))") {
            if let result = try anchor.extractSearchResultFromAnchor(baseURL: baseURL) {
                results.append(result)
            }
        }
        // Try fetching youtube results and insert at position 1
        if let youtubeResults = try main.extractYouTubeResults() {
            results.insert(contentsOf: youtubeResults, at: min(1, results.count))
        }
        return results
    }

    enum SearchError: Error {
        case invalidHTML
        case missingMainElement
    }
}

private extension Element {
    func extractYouTubeResults() throws -> [WebSearchResult]? {
        var results = [WebSearchResult]()
        // Search for elements with a href starting with https://www.youtube.com,
        // which contain a div role=heading
        let selector = "a[href^='https://www.youtube.com']:has(div[role=heading])"
        for element in try select(selector).array() {
            if let link = try? element.attr("href"),
               let parsed = URL(string: link),
               let title = try element.select("div[role=heading] span").first()?.text() {
                results.append(WebSearchResult(url: parsed, title: title, snippet: nil))
            }
        }
        return results
    }

    func extractSearchResultFromAnchor(baseURL: URL) throws -> WebSearchResult? {
        // First, extract the URL
        guard let href = try? attr("href"),
              let parsed = URL(string: href, relativeTo: baseURL)
        else {
            return nil
        }
        // Then, extract title:
        guard let title = try? select("h3").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        let snippet: String? = { () -> String? in
            guard let parent3 = self.parent()?.parent()?.parent() else { return nil }
            // First, look for an element with `div[style='-webkit-line-clamp:2']`
            if let div = try? parent3.select("div[style='-webkit-line-clamp:2']").first(),
               let text = try? div.text().nilIfEmptyOrJustWhitespace {
                return text
            }

            // If not, iterate backwards through child divs (except the first one) and look for one with a non-empty `<span>`
            let divChildren = Array(parent3.children().filter { $0.tagName() == "div" }[1...])
            for div in divChildren.reversed() {
                if let span = try? div.select("span").first(), let text = try? span.text().nilIfEmptyOrJustWhitespace {
                    return text
                }
            }
            return nil
        }()


        return WebSearchResult(url: parsed, title: title, snippet: snippet)
    }

    var firstDescendantWithInnerText: Element? {
        for child in children() {
            if child.hasChildTextNodes {
                return child
            }
            if let desc = child.firstDescendantWithInnerText {
                return desc
            }
        }
        return nil
    }

    var hasChildTextNodes: Bool {
        let nonBlankNodes = textNodes().filter { !$0.isBlank() }
        return !nonBlankNodes.isEmpty
    }

    var innerTextByDeletingLinks: String {
        let copy = self.copy() as! Element
        let links = (try? copy.select("a").array()) ?? []
        for link in links {
            // remove link el
            try? link.remove()
        }
        return (try? copy.text()) ?? ""
    }
}
