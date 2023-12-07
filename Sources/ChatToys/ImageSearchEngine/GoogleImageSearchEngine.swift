import Foundation
import Fuzi
import QuartzCore

public struct GoogleImageSearchEngine: ImageSearchEngine {
    public init() {
    }

    // MARK: - ImageSearchEngine
    public func searchImages(query: String) async throws -> [ImageSearchResult] {
        var urlComponents = URLComponents(string: "https://www.google.com/search")!
        urlComponents.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "tbm", value: "isch"), // to be matched = image search
            URLQueryItem(name: "gbv", value: "1"), // google basic version = 1 (no js)
        ]
        var request = URLRequest(url: urlComponents.url!)
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
//        let chromeUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36"
        let iosUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_1_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Mobile/15E148 Safari/604.1"
        request.setValue(iosUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw SearchError.invalidHTML
        }
        let baseURL = response.url ?? urlComponents.url!
        let extracted = try extract(html: html, baseURL: baseURL, query: query)
        return extracted
    }

    private func extract(html: String, baseURL: URL, query: String) throws -> [ImageSearchResult] {
        let doc = try Fuzi.HTMLDocument(string: html)
        print("START HTML:\n\(html)\nEND HTML")

        return doc.css("a[href]")
            .filter { $0.attr("href")?.starts(with: "/imgres") ?? false }
            .compactMap { el -> ImageSearchResult? in
            guard let href = el.attr("href"),
                  let comps = URLComponents(string: href),
                  let imgUrlStr = comps.queryItems?.first(where: { $0.name == "imgurl" })?.value,
                  let imgUrl = URL(string: imgUrlStr),
                  let siteUrlStr = comps.queryItems?.first(where: { $0.name == "imgrefurl" })?.value,
                  let siteUrl = URL(string: siteUrlStr)
            else {
                return nil
            }
//            // TODO: Set thumb url
//            let thumbnailSize: CGSize? = { () -> CGSize? in
//                guard let img = el.css("img[style]").first,
//                      let style = img.attr("style") 
//                else {
//                    return nil
//                }
//                // max-width:130px;max-height:70px
//                let parts = style.split(separator: ":")
//                if parts.count != 3 { return nil }
//                let p1 = String(parts[1]).components(separatedBy: "px").first!
//                let p2 = String(parts[2]).components(separatedBy: "px").first!
//                if let w = Float(p1), let h = Float(p2) {
//                    return CGSize(width: CGFloat(w), height: CGFloat(h))
//                }
//                return nil
//            }()
            // TODO: Scrape size of image aspect ratio
            return .init(imageURL: imgUrl, hostPageURL: siteUrl)
        }

        // document.querySelectorAll("a[href^='/imgres']")

        // /imgres?imgurl=https://upload.wikimedia.org/wikipedia/en/thumb/3/37/Arc_%2528browser%2529_logo.svg/1200px-Arc_%2528browser%2529_logo.svg.png&imgrefurl=https://en.wikipedia.org/wiki/Arc_(web_browser)&h=996&w=1200&tbnid=7Kx_DqZDmhyu_M&q=arc+browser&tbnh=204&tbnw=246&iact=rc&usg=AI4_-kThCbmTBRY39a-XUjJYmWz7AzJoVA&vet=1&docid=RtPfpSDC37dnAM&itg=1&tbm=isch&sa=X&ved=2ahUKEwiT4-iJ4_2CAxUTEGIAHbssBLcQrQN6BAgTEAE"


//        return .init(query: query, results: results, infoBox: infoBox)
    }

    enum SearchError: Error {
        case invalidHTML
    }
}
