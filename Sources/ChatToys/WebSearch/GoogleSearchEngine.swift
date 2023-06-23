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
        for anchor in try main.select("a:has(h3)") {
            if let result = try anchor.extractSearchResultFromAnchor(baseURL: baseURL) {
                results.append(result)
            }
        }
        return results
    }

    enum SearchError: Error {
        case invalidHTML
        case missingMainElement
    }
}

private extension Element {
    func extractSearchResultFromAnchor(baseURL: URL) throws -> WebSearchResult? {
        // First, extract the URL
        guard let href = try? attr("href"),
              let parsed = URL(string: href, relativeTo: baseURL)
//              let components = URLComponents(url: parsed, resolvingAgainstBaseURL: true),
//              let q = components.queryItems?.first(where: { $0.name == "q" }),
//              let url = URL(string: q.value ?? "", relativeTo: baseURL)
        else {
            return nil
        }
        // Then, extract title:
        guard let title = try? select("h3").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        let snippet: String? = {
            guard let parent = self.parent()?.parent()?.parent(),
                  let secondDiv = parent.children().filter({ $0.tagName() == "div" }).get(1),
                  let text = secondDiv.innerTextByDeletingLinks.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            else { return nil }
            return text
    
        }()
//        // Finally, extract snippet:
//              let text = secondDiv.innerTextByDeletingLinks.trimmingCharacters(in: .whitespacesAndNewlines)
//            //   let snippetNode = secondDiv.firstDescendantWithInnerText,
//            //   let text = try? snippetNode.text().trimmingCharacters(in: .whitespacesAndNewlines)
//        else {
//            return nil
//        }

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
