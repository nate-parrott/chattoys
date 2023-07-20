import Foundation

public struct OpenAIEmbedder: Embedder {
    public struct Options {
        public var printCost: Bool
        public var truncateToFitTokenLimit: Bool

        public init(printCost: Bool = false, truncateToFitTokenLimit: Bool = false) {
            self.printCost = printCost
            self.truncateToFitTokenLimit = truncateToFitTokenLimit
        }
    }

    let credentials: OpenAICredentials
    var options: Options

    public init(credentials: OpenAICredentials, options: Options = .init()) {
        self.credentials = credentials
        self.options = options
    }

    // MARK: - Embedder

    public func embed(documents: [String]) async throws -> [Embedding] {
        /*
         curl https://api.openai.com/v1/embeddings \
           -H "Authorization: Bearer $OPENAI_API_KEY" \
           -H "Content-Type: application/json" \
           -d '{
             "input": "The food was delicious and the waiter...",
             "model": "text-embedding-ada-002"
           }'
         */
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/embeddings")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = Request(input: documents)
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
        var model = "text-embedding-ada-002"
        var input: [String]
    }

    private struct Response: Codable {
        struct Data: Codable {
            var embedding: [Double]
            var index: Int
        }

        struct Usage: Codable {
            var prompt_tokens: Int
        }

        var data: [Data]
        var usage: Usage
//        {
//          "object": "list",
//          "data": [
//            {
//              "object": "embedding",
//              "embedding": [
//                0.0023064255,
//                -0.009327292,
//                .... (1536 floats total for ada-002)
//                -0.0028842222,
//              ],
//              "index": 0
//            }
//          ],
//          "model": "text-embedding-ada-002",
//          "usage": {
//            "prompt_tokens": 8,
//            "total_tokens": 8
//          }
//        }
    }
}
