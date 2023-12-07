import Foundation

extension BingSearchEngine: ImageSearchEngine {
    public func searchImages(query: String) async throws -> [ImageSearchResult] {
        let endpoint = "https://api.bing.microsoft.com/"
        let count = 10
        var urlComponents = URLComponents(string: endpoint + "/v7.0/images/search")!
        urlComponents.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "mkt", value: "en-US"),
            // URLQueryItem(name: "responseFilter", value: "Webpages"),
            URLQueryItem(name: "count", value: "\(count)"),
        ]
        var request = URLRequest(url: urlComponents.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        let (data, _) = try await URLSession.shared.data(for: request)

        // Pretty-print data to the console as json
//        let json = try JSONSerialization.jsonObject(with: data, options: [])
//        let prettyData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
//        print(String(data: prettyData, encoding: .utf8)!)

        let response = try JSONDecoder().decode(BingAPIImageResponse.self, from: data)
        return response.value.compactMap { result in
            var size: CGSize? = nil
            if let w = result.width, let h = result.height {
                size = .init(width: w, height: h)
            }
            return .init(thumbnailURL: result.thumbnailUrl, imageURL: result.contentUrl, hostPageURL: result.hostPageUrl, size: size)
        }
    }
}

private struct BingAPIImageResponse: Codable {
    var totalEstimatedMatches: Int?
    var nextOffset: Int?
    var value: [BingAPIResponse.ImageResult]
}
