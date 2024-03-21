import Foundation

public struct OpenAIEmbedder: Embedder {
    public struct Options {
        public var printCost: Bool
        public var truncateToFitTokenLimit: Bool
        public var model: Model
        public var dimensions: Int?

        public enum Model: String {
            case textEmbeddingAda002 = "text-embedding-ada-002"
            case textEmbedding3Small = "text-embedding-3-small"
            case textEmbedding3Large = "text-embedding-3-large"

            var maxDimensions: Int {
                switch self {
                case .textEmbeddingAda002, .textEmbedding3Small, .textEmbedding3Large: return 1536
                }
            }
        }

        public init(printCost: Bool = false, truncateToFitTokenLimit: Bool = false, model: Model = .textEmbeddingAda002, dimensions: Int? = nil) {
            self.printCost = printCost
            self.truncateToFitTokenLimit = truncateToFitTokenLimit
            self.model = model
            self.dimensions = dimensions
        }
    }

    public var dimensions: Int {
        options.dimensions ?? options.model.maxDimensions
    }

    let credentials: OpenAICredentials
    var options: Options

    public init(credentials: OpenAICredentials, options: Options = .init()) {
        self.credentials = credentials
        self.options = options
    }

    // MARK: - Embedder

    public func embed(documents: [String]) async throws -> [Embedding] {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/embeddings")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = Request(model: options.model.rawValue, input: documents, dimensions: options.dimensions)
        request.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(Response.self, from: data)

        if options.printCost {
            // $0.0001 per 1k tokens
            // Print cost per 1k
            let count = response.usage.prompt_tokens
            let dollars = Double(count) * 0.0001
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = "USD"
            formatter.maximumFractionDigits = 4
            let cost = formatter.string(from: NSNumber(value: dollars))!
            print("[OpenAI Embeddings]: This request used \(count) tokens to embed \(documents.count) documents. If you ran this request 1000 times, it would cost \(cost).")
        }

        enum EmbeddingError: Error {
            case wrongNumberOfResponses
        }

        guard response.data.count == documents.count else {
            throw EmbeddingError.wrongNumberOfResponses
        }

        return response.data.map { Embedding(vectors: $0.embedding, provider: "openai-\(body.model)") }
    }

    public var tokenLimit: Int { 8191 }

    private struct Request: Codable {
        var model: String
        var input: [String]
        var dimensions: Int?
    }

    private struct Response: Codable {
        struct Data: Codable {
            var embedding: [Float]
            var index: Int
        }

        struct Usage: Codable {
            var prompt_tokens: Int
        }

        var data: [Data]
        var usage: Usage
    }
}
