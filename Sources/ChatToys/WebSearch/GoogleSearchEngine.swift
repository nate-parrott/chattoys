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
        request.setValue("utf-8, iso-8859-1;q=0.5", forHTTPHeaderField: "Accept-Charset")
        let userAgent = "Lynx/2.8.8dev.3 libwww-FM/2.14 SSL-MM/1.4.1"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
//        print("[N] Making Google Request '\(query)'")
        let (data, response) = try await session.data(for: request)
        guard let html = String(data: data, encoding: .isoLatin1) else {
            throw SearchError.invalidHTML
        }
//        print("[BEGIN HTML]")
//        print(html)
//        print("[END HTML]")
        let baseURL = response.url ?? urlComponents.url!

//        let t2 = CACurrentMediaTime()
        let extracted = try extract(html: html, baseURL: baseURL, query: query)
//        print("[Timing] [GoogleSearch] Parsed at \(CACurrentMediaTime() - t2)")
        
        var resp = extracted
        resp.html = html
        return resp
    }

    func extract(html: String, baseURL: URL, query: String) throws -> WebSearchResponse {
        let doc = try Fuzi.HTMLDocument(stringSAFE: html)
        var results = [WebSearchResult]()
        
        // Parse search results with the following structure:
        // <a href="/url?q=..."><span>Title</span></a> then parent.parent has <table> with snippet
        for anchor in doc.xpath("//a") {
            guard let href = anchor.attr("href"),
                  href.hasPrefix("/url?q="),
                  let components = URLComponents(string: href),
                  let urlStr = components.queryItems?.first(where: { $0.name == "q" })?.value,
                  let url = URL(string: urlStr),
                  let span = anchor.css("span").first,
                  let title = span.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyOrJustWhitespace,
                  let parentParent = anchor.nthParent(2),
                  let table = parentParent.css("table").first,
                  let snippet = table.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyOrJustWhitespace
            else { continue }
            
            results.append(WebSearchResult(url: url, title: title, snippet: snippet))
        }
        
        return .init(query: query, results: results, infoBox: nil)
    }

    enum SearchError: Error {
        case invalidHTML
        case missingMainElement
    }
}

private extension Fuzi.XMLElement {
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
