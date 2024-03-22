import Foundation

public protocol Embedder {
    func embed(documents: [String]) async throws -> [Embedding]
    var tokenLimit: Int { get } // aka context size
    var dimensions: Int { get }
    var providerString: String { get }
}
