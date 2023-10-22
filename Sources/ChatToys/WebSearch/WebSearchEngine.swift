import Foundation

public struct WebSearchResponse: Equatable, Codable {
    public var query: String
    public var results: [WebSearchResult]
    public var infoBox: String?
}

public struct WebSearchResult: Equatable, Codable, Identifiable {
    public var id: URL { url }
    public var url: URL
    public var title: String
    public var snippet: String?

    public init(url: URL, title: String, snippet: String?) {
        self.url = url
        self.title = title
        self.snippet = snippet
    }
}

public extension WebSearchResult {
    static func stub(id: Int) -> Self {
        Self(
            url: URL(string: "https://example.com/\(id)")!,
            title: "Example site \(id)",
            snippet: "Example snippet \(id). Lorem ipsum dolor sit amet. Consectetur adipiscing elit."
        )
    }

    static func stubArticle(id: Int) -> Self {
        Self(
            url: URL(string: "https://www.nytimes.com/2021/04/15/arts/design/Met-museum-roof-garden-da-corte.html?x=\(id)")!,
            title: "On the Met's Roof, a Wistful Fantasty We've Been Waiting For",
            snippet: "Example snippet \(id). Lorem ipsum dolor sit amet. Consectetur adipiscing elit."
        )
    }
}

extension WebSearchResult: CustomStringConvertible {
    public var description: String {
        let lines: [String] = [
            " - [\(url.host ?? "?")]",
            "   \(title)",
            "   \(snippet?.truncateTail(maxLen: 80) ?? "[No snippet]")"
        ]
        return lines.joined(separator: "\n")
    }
}

public protocol WebSearchEngine {
    func search(query: String) async throws -> WebSearchResponse
}
