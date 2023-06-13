import Foundation

public struct ImageSearchResult: Equatable, Codable, Identifiable {
    public var id: URL { imageURL }
    public var thumbnailURL: URL?
    public var imageURL: URL
    public var hostPageURL: URL
    public var size: CGSize?
}

public extension ImageSearchResult {
    static func stub(id: Int) -> Self {
        Self(thumbnailURL: nil, imageURL: URL(string: "https://m.media-amazon.com/images/I/516AYp3mmQL.jpg")!, hostPageURL: URL(string: "https://uphoto.com/index.php/product/occer-12x25-compact-binoculars-with-clear-low-light-vision/")!, size: nil)
    }
}

public protocol ImageSearchEngine {
    func searchImages(query: String) async throws -> [ImageSearchResult]
}
