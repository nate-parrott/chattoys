import Foundation

public struct LLMMessage: Equatable, Codable {
    public enum Role: String, Equatable, Codable, Hashable {
        case system
        case user
        case assistant
    }

    public var role: Role
    public var content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

public protocol ChatLLM {
    func completeStreaming(prompt: [LLMMessage]) -> AsyncThrowingStream<LLMMessage, Error>
    var tokenLimit: Int { get } // aka context size
}

public extension ChatLLM {
    // We can't currently run the real tokenizer on device, so token counts are estimates. You should leave a little 'wiggle room'
    var tokenLimitWithWiggleRoom: Int {
        max(1, Int(round(Double(tokenLimit) * 0.85)) - 50)
    }

    func complete(prompt: [LLMMessage]) async throws -> LLMMessage {
        var last: LLMMessage?
        for try await partial in completeStreaming(prompt: prompt) {
            last = partial
        }
        guard let last else {
            throw LLMError.unknown
        }
        return last
    }
}


public enum LLMError: Error {
    case tooManyTokens
    case http(Int)
    case unknown
}
