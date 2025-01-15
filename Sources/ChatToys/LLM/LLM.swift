import AnyCodable
import Foundation

public struct LLMMessage: Equatable, Codable {
    public enum Role: String, Equatable, Codable, Hashable {
        case system
        case user
        case assistant
        case function
    }

    public struct FunctionCall: Equatable, Codable, Hashable {
        public var id: String?
        public var name: String
        public var arguments: String // as json

        public init(id: String? = nil, name: String, arguments: String) {
            self.id = id
            self.name = name
            self.arguments = arguments
        }

        public var argumentsJson: Any? {
            try? JSONSerialization.jsonObject(with: arguments.data(using: .utf8)!)
        }

        public var argumentsAsAnyCodable: AnyCodable? {
            try? JSONDecoder().decode(AnyCodable.self, from: arguments.data(using: .utf8)!)
        }

        public func argument<T>(name: String, type: T.Type) -> T? {
            if let params = argumentsJson as? [String: Any], let val = params[name] as? T {
                return val
            }
            return nil
        }

        public func decodeArguments<T: Codable>(as kind: T.Type, stream: Bool) -> T? {
            let args = stream ? self.arguments.capJson : self.arguments
            // When functions have no args, the args JSON may be an empty string
            let argsOrEmptyDict = args.nilIfEmpty ?? "{}"
            return try? JSONDecoder().decode(kind, from: Data(argsOrEmptyDict.utf8))
        }
    }

    public struct FunctionResponse: Equatable, Codable {
        public var id: String?
        public var functionName: String
        public var text: String

        public init(id: String?, functionName: String, text: String) {
            self.id = id
            self.functionName = functionName
            self.text = text
        }
    }

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

    public struct Audio: Equatable, Codable {
        public enum AudioFormat: String, Equatable, Codable {
            case mp3
            case wav
        }

        public var format: AudioFormat
        public var data: Data

        public init(format: AudioFormat, data: Data) {
            self.format = format
            self.data = data
        }
    }

    public var role: Role
    public var content: String
    public var images = [Image]() // For multimodal models. URLs can be base64
    public var inputAudio = [Audio]()

    // For role=assistant
    public var functionCalls: [FunctionCall] = []

    // For role=function
    public var functionResponses: [FunctionResponse] = []

    // MARK: Initializers

    public init(assistantMessageWithContent content: String, functionCalls: [FunctionCall] = []) {
        self.role = .assistant
        self.content = content
        self.functionCalls = functionCalls
    }

    public init(functionResponses: [FunctionResponse]) {
        self.role = .function
        self.functionResponses = functionResponses
        self.content = ""
    }

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }

    // TODO: Deprecate
    public init(role: Role, content: String, functionCall: FunctionCall? = nil, nameOfFunctionThatProduced: String? = nil) {
        self.role = role
        self.functionCalls = functionCall != nil ? [functionCall!] : []

        if let nameOfFunctionThatProduced {
            self.content = ""
            self.functionResponses = [.init(id: nil, functionName: nameOfFunctionThatProduced, text: content)]
        } else {
            self.content = content
        }
    }
}

extension LLMMessage {
    // Deprecated; use the array instead
    public var functionCall: FunctionCall? {
        get { functionCalls.first }
        set {
            if let newValue {
                functionCalls = [newValue]
            } else {
                functionCalls = []
            }
        }
    }
    // Deprecated; use functionResponse instead
    public var nameOfFunctionThatProduced: String? {
        get { functionResponses.first?.functionName }
        set {
            if let newValue {
                functionResponses = [.init(id: nil, functionName: newValue, text: content)]
                self.content = ""
            } else {
                self.functionResponses = []
            }
        }
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
