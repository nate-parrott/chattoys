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
}

public enum LLMError: Error {
    case tooManyTokens
    case http(Int)
    case unknown
}
