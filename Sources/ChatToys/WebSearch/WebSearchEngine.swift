import Foundation

public struct WebSearchResult: Equatable, Codable, Identifiable {
    public var id: URL { url }
    public var url: URL
    public var title: String
    public var snippet: String?
}

public protocol WebSearchEngine {
    func search(query: String) async throws -> [WebSearchResult]
}
