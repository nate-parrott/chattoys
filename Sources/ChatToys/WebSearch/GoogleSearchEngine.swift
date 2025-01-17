import Foundation
import SwiftSoup
import QuartzCore
import Fuzi

public struct GoogleSearchEngine: WebSearchEngine {
    public init() {
    }

    // MARK: - WebSearchEngine
    public func search(query: String) async throws -> WebSearchResponse {
        var urlComponents = URLComponents(string: "https://www.google.com/search")!
        urlComponents.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "udm", value: "14"),
            URLQueryItem(name: "gbv", value: "1"), // google basic version = 1 (no js)
        ]
        let session = URLSession(configuration: .ephemeral)
        var request = URLRequest(url: urlComponents.url!)
        request.httpShouldHandleCookies = false
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let chromeUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
        request.setValue(chromeUserAgent, forHTTPHeaderField: "User-Agent")
        print("[N] Making Google Request '\(query)'")
        let (data, response) = try await session.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw SearchError.invalidHTML
        }
        print("[BEGIN HTML]")
        print(html)
        print("[END HTML]")
        let baseURL = response.url ?? urlComponents.url!

        let t2 = CACurrentMediaTime()
        let extracted = try extract(html: html, baseURL: baseURL, query: query)
//        print("[Timing] [GoogleSearch] Parsed at \(CACurrentMediaTime() - t2)")
        
        var resp = extracted
        resp.html = html
        return resp
    }

    func extract(html: String, baseURL: URL, query: String) throws -> WebSearchResponse {
//        let doc = try SwiftSoup.parse(html, baseURL.absoluteString)
        let doc = try Fuzi.HTMLDocument(stringSAFE: html)

        guard let main = doc.css("#main").first else {
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

        // a:has(h3:not([role=heading], [aria-hidden=true]))
        let anchors = main.css("a").filter { el in
            let h3s = el.css("h3")
                .filter { $0.attr("role") != "header" && $0.attr("aria-hidden") != "true" }
            return h3s.count > 0
        }
        for anchor in anchors {
            if let result = try anchor.extractSearchResultFromAnchor(baseURL: baseURL) {
                results.append(result)
            }
        }

//        for anchor in try main.css("a:has(h3:not([role=heading], [aria-hidden=true]))") {
//            if let result = try anchor.extractSearchResultFromAnchor(baseURL: baseURL) {
//                results.append(result)
//            }
//        }
        // Try fetching youtube results and insert at position 1
        if let youtubeResults = try main.extractYouTubeResults() {
            results.insert(contentsOf: youtubeResults, at: min(1, results.count))
        }

//        var infoBox: String?
//        if let kp = try? main.select(".kp-header").first()?.text().nilIfEmptyOrJustWhitespace {
//            infoBox = kp
//        }

        return .init(query: query, results: results, infoBox: nil)
    }

    enum SearchError: Error {
        case invalidHTML
        case missingMainElement
    }
}

private extension Fuzi.XMLElement {
    func extractYouTubeResults() throws -> [WebSearchResult]? {
        var results = [WebSearchResult]()
        // Search for elements with a href starting with https://www.youtube.com,
        // which contain a div role=heading
        // a[href^='https://www.youtube.com']:has(div[role=heading])
        for element in css("a[href]") {
//            guard element.attr("href")?.hasPrefix("https://www.youtube.com") ?? false,
//                  element.css("div[role='header']").count > 0
//            else { continue }

            if let link = element.attr("href"),
               link.hasPrefix("https://www.youtube.com"),
               let parsed = URL(string: link),
               let title = element.css("div[role='heading'] span").first?.stringValue {
                results.append(WebSearchResult(url: parsed, title: title, snippet: nil))
            }
        }
        return results
    }

    func extractSearchResultFromAnchor(baseURL: URL) throws -> WebSearchResult? {
        // First, extract the URL
        guard let href = attr("href"),
              let parsed = URL(string: href, relativeTo: baseURL)
        else {
            return nil
        }
        // Then, extract title:
        guard let title = css("h3").first?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        let snippet: String? = { () -> String? in
            guard let farParent = self.nthParent(5) else { return nil }
            // First, look for an element with `div[style='-webkit-line-clamp:2']`
            if let div = farParent.css("div[style='-webkit-line-clamp:2']").first,
               let text = div.stringValue.nilIfEmptyOrJustWhitespace {
                return text
            }

            // If not, iterate backwards through child divs (except the first one) and look for one with a non-empty `<span>`
            let divChildren = Array(farParent.children.filter { $0.tag == "div" }.dropFirst())
            for div in divChildren.reversed() {
                if let span = div.css("span").first, let text = span.stringValue.nilIfEmptyOrJustWhitespace {
                    return text
                }
            }
            return nil
        }()


        return WebSearchResult(url: parsed, title: title, snippet: snippet)
    }

    var firstDescendantWithInnerText: Fuzi.XMLElement? {
        for child in children {
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
        let nonBlankNodes = childNodes(ofTypes: [.Text]).filter { $0.stringValue.nilIfEmptyOrJustWhitespace != nil }
        return !nonBlankNodes.isEmpty
    }

//    var innerTextByDeletingLinks: String {
//        let copy = self.copy() as! Element
//        let links = (try? copy.select("a").array()) ?? []
//        for link in links {
//            // remove link el
//            try? link.remove()
//        }
//        return (try? copy.text()) ?? ""
//    }

    func nthParent(_ n: Int) -> Fuzi.XMLElement? {
        if n <= 0 {
            return self
        }
        return parent?.nthParent(n - 1)
    }
}

extension HTMLDocument {
    // Work around iOS 18 crash when doing HTMLDocument(string: ...) directly
    // Seems to be fine if you convert the string to data first
    public convenience init(stringSAFE: String) throws {
        try self.init(data: Data(stringSAFE.utf8))
    }
}
