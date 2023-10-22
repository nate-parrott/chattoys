import Foundation

public struct BingSearchEngine: WebSearchEngine {
    public var apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - WebSearchEngine
    public func search(query: String) async throws -> WebSearchResponse {
        let count = 10
        let endpoint = "https://api.bing.microsoft.com/"
        var urlComponents = URLComponents(string: endpoint + "/v7.0/search")!
        urlComponents.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "mkt", value: "en-US"),
            URLQueryItem(name: "count", value: "\(count)"),
        ]
        var request = URLRequest(url: urlComponents.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        let (data, _) = try await URLSession.shared.data(for: request)

        let response = try JSONDecoder().decode(BingAPIResponse.self, from: data)
        let results: [WebSearchResult] = response.webPages?.value.map { WebSearchResult(url: $0.url, title: $0.name, snippet: $0.snippet) } ?? []

        // TODO: Add info box from response
        return .init(results: results, infoBox: nil)
    }
}

struct BingAPIResponse: Codable {
    struct TimezoneResult: Codable {
        struct PrimaryCityTime: Codable {
            let utcOffset: String
            let timeZoneName: String
            let location: String
            let time: String
        }
        let primaryCityTime: PrimaryCityTime?
    }
    var timeZone: TimezoneResult?

    // TODO: translations, news?
    struct PlaceResult: Codable, Identifiable {
        struct Address: Codable {
            var neighborhood: String?
            var addressLocality: String?
            var addressRegion: String?
            var addressCountry: String?
            var postalCode: String?
        }

        struct EntityPresentationInfo: Codable {
            var entityScenario: String
            var entityTypeHints: [String]
        }

        var entityPresentationInfo: EntityPresentationInfo?
        var address: Address?
        // var webSearchUrl: String
        var id: String
        var telephone: String?
        var name: String
        var url: URL?
    }

    struct Thumbnail: Codable {
        var width: Int
        var height: Int
    }

    struct ImageResult: Codable, Identifiable {
        var id: String { contentUrl.absoluteString }
        var contentUrl: URL
        var name: String
        var thumbnailUrl: URL
        // var webSearchUrl: String
        var hostPageUrl: URL
        // var hostPageDisplayUrl: String
        // var datePublished: Date
        // var contentSize: String
        // var encodingFormat: String
        var width: Int?
        var height: Int?
        var thumbnail: Thumbnail?
    }

    struct WebResult: Codable, Identifiable {
        var id: String
        let name: String
        let url: URL
        let displayUrl: String
        let snippet: String
        let isFamilyFriendly: Bool
    }

    struct ComputationResult: Codable, Identifiable {
        var id: String
        let expression: String
        let value: String
    }
    var computation: ComputationResult? = nil

    struct Web: Codable {
        let value: [WebResult]
    }
    var webPages: Web? = nil

    struct Video: Codable, Identifiable {
        var thumbnail: Thumbnail
        var thumbnailUrl: URL
        var contentUrl: URL?
        var hostPageUrl: URL?
        var datePublished: String?
        var embedHtml: String?
        var name: String?
        var description: String?
        var duration: String? // like "PT2M39S"

        var id: String { (hostPageUrl ?? contentUrl)?.absoluteString ?? "?" }
    }

    struct Videos: Codable {
        var id: String
        var value: [Video]
    }
    var videos: Videos?

    struct Images: Codable {
        let value: [ImageResult]
    }
    var images: Images? = nil

    struct Places: Codable {
        let value: [PlaceResult]
    }
    var places: Places? = nil
}
