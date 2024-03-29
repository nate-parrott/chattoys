import Foundation

public struct LLMMessage: Equatable, Codable {
    public enum Role: String, Equatable, Codable, Hashable {
        case system
        case user
        case assistant
        case function // OpenAI only
    }

    public var role: Role
    public var content: String
    public var functionCall: FunctionCall?
    public var nameOfFunctionThatProduced: String?

    public struct Image: Equatable, Codable {
        public enum Detail: String, Equatable, Codable {
            case auto = "auto"
            case high = "high"
            case low = "low"
        }
        public var url: URL
        public var detail: Detail?

        public init(url: URL, detail: Detail? = .auto) {
            self.url = url
            self.detail = detail
        }
    }

    public var images = [Image]() // For multimodal models. URLs can be base64

    public struct FunctionCall: Equatable, Codable, Hashable {
        public var name: String
        public var arguments: String // as json

        public var argumentsJson: Any? {
            try? JSONSerialization.jsonObject(with: arguments.data(using: .utf8)!)
        }

        public func argument<T>(name: String, type: T.Type) -> T? {
            if let params = argumentsJson as? [String: Any], let val = params[name] as? T {
                return val
            }
            return nil
        }
    }

    public init(role: Role, content: String, functionCall: FunctionCall? = nil, nameOfFunctionThatProduced: String? = nil) {
        self.role = role
        self.content = content
        self.functionCall = functionCall
        self.nameOfFunctionThatProduced = nameOfFunctionThatProduced
    }
}

public protocol ChatLLM {
    func completeStreaming(prompt: [LLMMessage]) -> AsyncThrowingStream<LLMMessage, Error>
    var tokenLimit: Int { get } // aka context size

    // If the LLM supports specific JSON conditioning, this should invoke it. Default impl calls `completeStreaming` normally
    func completeStreamingWithJsonHint(prompt: [LLMMessage]) -> AsyncThrowingStream<LLMMessage, Error>
}

public extension ChatLLM {
    // We can't currently run the real tokenizer on device, so token counts are estimates. You should leave a little 'wiggle room'
    var tokenLimitWithWiggleRoom: Int {
        max(1, Int(round(Double(tokenLimit) * 0.85)) - 50)
    }

    // default implementation, can be overriden
    func completeStreamingWithJsonHint(prompt: [LLMMessage]) -> AsyncThrowingStream<LLMMessage, Error> {
        completeStreaming(prompt: prompt)
    }

    func complete(prompt: [LLMMessage]) async throws -> LLMMessage {
        var last: LLMMessage?
        for try await partial in completeStreaming(prompt: prompt) {
            last = partial
        }
        guard let last else {
            throw LLMError.unknown(nil)
        }
        return last
    }
}

public enum LLMError: Error, Equatable {
    case tooManyTokens
    case http(Int)
    case unknown(String?)
}
