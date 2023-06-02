import Foundation

public struct WebSearchResult: Equatable, Codable, Identifiable {
    public var id: URL { url }
    public var url: URL
    public var title: String
    public var snippet: String?
}

public extension WebSearchResult {
    static func stub(id: Int) -> Self {
        Self(
            url: URL(string: "https://example.com/\(id)")!,
            title: "Example site \(id)",
            snippet: "Example snippet \(id). Lorem ipsum dolor sit amet. Consectetur adipiscing elit."
        )
    }
}

public protocol WebSearchEngine {
    func search(query: String) async throws -> [WebSearchResult]
}
