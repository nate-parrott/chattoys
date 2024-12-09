import Foundation

public struct CompletionOption: Equatable, Codable, Hashable {
    public var completion: String
    public var logProb: Double
}

extension ChatGPT {
    public func completeWithOptions(_ n: Int, prompt: [LLMMessage]) async throws -> [CompletionOption] {
        let req = try createChatRequest(prompt: prompt, functions: [], stream: false, n: n, logProbs: true)
        let (data, _) = try await URLSession.shared.data(for: req)
        let response = try JSONDecoder().decode(NonStreamingResponse.self, from: data)
        return response.choices.compactMap { choice in
            if let prob = choice.logProb {
                return .init(completion: choice.message.contentAsText, logProb: prob)
            }
            return nil
        }
        .sorted(by: { $0.logProb > $1.logProb })
        .deduplicate { $0 }
    }
}
