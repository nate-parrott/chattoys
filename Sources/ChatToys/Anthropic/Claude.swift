import Foundation
import AnyCodable

public struct AnthropicCredentials {
    var apiKey: String
    var orgId: String?

    public init(apiKey: String) {
        self.apiKey = apiKey
    }
}

public typealias ClaudeNewAPI = Claude

// Uses new message-based claude API
public struct Claude {
    static let DEBUG = false

    public enum Model: Equatable {
        case claudeInstant12
        case claude2
        case claude3Haiku // small
        case claude3Sonnet // medium
        case claude3Opus // large
        case custom(String /* model id */, Int /* token limit */)

        var modelId: String {
            switch self {
            case .claudeInstant12: return "claude-instant-1.2"
            case .claude2: return "claude-2"
            case .claude3Haiku: return "claude-3-haiku-20240307"
            case .claude3Sonnet: return "claude-3-sonnet-20240229"
            case .claude3Opus: return "claude-3-opus-20240229"
            case .custom(let id, _): return id
            }
        }
    }

    public struct Options {
        public var model: Model
        public var maxTokens: Int
        public var stopSequences: [String]
        public var temperature: Double
        public var printToConsole: Bool
        public var responsePrefix: String // Forces the model to use this as the beginning of the response. (This prefix _will_ be included in the output).
        public var stream: Bool

        public init(model: Model = .claudeInstant12, maxTokens: Int = 1000, stopSequences: [String] = [], temperature: Double = 0.5, printToConsole: Bool = false, responsePrefix: String = "", stream: Bool = true) {
            self.model = model
            self.maxTokens = maxTokens
            self.stopSequences = stopSequences
            self.temperature = temperature
            self.printToConsole = printToConsole
            self.responsePrefix = responsePrefix
            self.stream = stream
        }
    }

    public var credentials: AnthropicCredentials
    public var options: Options

    public init(credentials: AnthropicCredentials, options: Options = Options()) {
        self.credentials = credentials
        self.options = options
    }
}

extension Claude: ChatLLM, FunctionCallingLLM {
    private struct Request: Encodable {
        var messages: [ClaudeMessage]
        var system: String?
        var model: String
        var max_tokens: Int
        var stop_sequences: [String]?
        var temperature: Double
        var stream: Bool
        var tools: [ClaudeTool] = []
    }

    private struct Response: Codable {
        var content: [ClaudeMessage.Content]
    }

    public var tokenLimit: Int {
        switch options.model {
        case .claudeInstant12, .claude2: return 100_000
        case .claude3Sonnet, .claude3Opus, .claude3Haiku: return 200_000
        case .custom(_, let limit): return limit
        }
    }

    enum ClaudeError: Error {
        case emptyResponseText
    }

    // MARK: - ChatLLM
    public func complete(prompt: [LLMMessage]) async throws -> LLMMessage {
        try await complete(prompt: prompt, functions: [])
    }

    public func completeStreaming(prompt: [LLMMessage]) -> AsyncThrowingStream<LLMMessage, Error> {
        completeStreaming(prompt: prompt, functions: [])
    }

    // MARK: - FunctionCallingLLM
    public func complete(prompt: [LLMMessage], functions: [LLMFunction]) async throws -> LLMMessage {
        let request = try createRequest(prompt: prompt, stream: false, functions: functions)
        let (data, response) = try await URLSession.shared.data(for: request)
        if Self.DEBUG {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("[Anthropic] Failed with error: \(String(data: data, encoding: .utf8)!)")
            }
        }
        let resp = try JSONDecoder().decode(Response.self, from: data)
        let text = resp.content.first(where: { $0.type == .text })?.text ?? ""
        let functionCalls = resp.content.filter { $0.type == .tool_use }.compactMap { $0.asFunctionCall }
//        guard let text = resp.content.first?.text else {
//            throw ClaudeError.emptyResponseText
//        }

        return LLMMessage(assistantMessageWithContent: options.responsePrefix + text, functionCalls: functionCalls)
    }

    public func completeStreaming(prompt: [LLMMessage], functions: [LLMFunction]) -> AsyncThrowingStream<LLMMessage, Error> {
        if Self.DEBUG {
            return AsyncThrowingStream { cont in
                Task {
                    do {
                        let res = try await self.complete(prompt: prompt, functions: functions)
                        cont.yield(res)
                        cont.finish()
                    } catch {
                        cont.finish(throwing: error)
                    }
                }
            }
        }

        let request: URLRequest
        do {
            request = try createRequest(prompt: prompt, stream: true, functions: functions)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        return AsyncThrowingStream<LLMMessage, any Error> { continuation in
            let src = EventSource(urlRequest: request)

            // The Claude API supports returning multiple messages with multiple content blocks. We don't support that yet so we just return a single textual message.
            var messages = [LLMMessage]()

            /*
             Event formats:

             event: message_start
             data: {"type": "message_start", "message": {"id": "msg_1nZdL29xx5MUA1yADyHTEsnR8uuvGzszyY", "type": "message", "role": "assistant", "content": [], "model": "claude-3-opus-20240229", "stop_reason": null, "stop_sequence": null, "usage": {"input_tokens": 25, "output_tokens": 1}}}

             event: content_block_start
             data: {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}

             event: ping
             data: {"type": "ping"}

             event: content_block_delta
             data: {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Hello"}}

             event: content_block_delta
             data: {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "!"}}

             event: content_block_delta
             data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"location\":"}}

             event: content_block_stop
             data: {"type": "content_block_stop", "index": 0}

             event: message_delta
             data: {"type": "message_delta", "delta": {"stop_reason": "end_turn", "stop_sequence":null, "usage":{"output_tokens": 15}}}

             event: message_stop
             data: {"type": "message_stop"}
             */

            src.addEventListener("error") { id, event, data in
                print("[CS] error: \(data ?? "")")
                continuation.finish(throwing: LLMError.unknown(data))
            }

            // Used for both message_start and message_stop
            struct PartialMessage: Codable {
                var id: String?
                var role: ClaudeRole?
            }

            func modifyLastMessageAndYield(_ block: (inout LLMMessage) -> Void) {
                guard var last = messages.last else { return }
                block(&last)
                messages[messages.count - 1] = last
                continuation.yield(last)
            }

            func tryDecode<Body: Codable>(data: String?, type: Body.Type) -> Body? {
                // If we can't decode, send an error to the continuation
                do {
                    return try JSONDecoder().decode(Body.self, from: Data((data ?? "").utf8))
                } catch {
                    print("Failed trying to decode: \(data ?? "[empty str]"); error \(error)")
                    continuation.finish(throwing: error)
                    return nil
                }
            }

            src.addEventListener("message_start") { id, event, data in
//                print("[CS] message_start: \(data ?? "")")
                struct MessageStart: Codable {
                    var message: PartialMessage
                }
                if let message = tryDecode(data: data, type: MessageStart.self) {
                    messages.append(LLMMessage(role: message.message.role?.asLLMRole ?? .assistant, content: ""))
                }
            }

            src.addEventListener("content_block_start") { id, event, data in
//                print("[CS] content_block_start: \(data ?? "")")
                struct ContentBlockStart: Codable {
                    var index: Int
                    var content_block: ContentBlock

                    struct ContentBlock: Codable {
                        var type: String // e.g. text or tool_use
                        var text: String? // for type=text
                        var id: String? // for type=tool_use
                        var name: String? // for type=tool_use
                        var input: AnyCodable? // for type=tool_use; ignored since empty at beginning
                    }
                }
                if let block = tryDecode(data: data, type: ContentBlockStart.self) {
                    switch block.content_block.type {
                    case "text":
                        if let text = block.content_block.text {
                            // If this is the first content block of the first message, prepend the response prefix
                            if messages.count == 1, messages[0].content.isEmpty {
                                messages[0].content += options.responsePrefix
                            }
                            modifyLastMessageAndYield { $0.content += text }
                        }
                    case "tool_use":
                        if let name = block.content_block.name, let id = block.content_block.id {
                            modifyLastMessageAndYield { $0.functionCalls.append(.init(id: id, name: name, arguments: "")) }
                        }
                    default: () // not expected
                    }

                }
            }

            src.addEventListener("content_block_delta") { id, event, data in
//                print("[CS] content_block_delta: \(data ?? "")")
                struct ContentBlockDelta: Codable {
                    var index: Int
                    var delta: ContentDelta

                    struct ContentDelta: Codable {
                        var type: String // e.g. text_delta or input_json_delta
                        var text: String?
                        var partial_json: String?
                    }
                }
                if let delta = tryDecode(data: data, type: ContentBlockDelta.self) {
                    switch delta.delta.type {
                    case "text_delta":
                        if let text = delta.delta.text {
                            modifyLastMessageAndYield { $0.content += text }
                        }
                    case "input_json_delta":
                        if let partial = delta.delta.partial_json {
                            modifyLastMessageAndYield { $0.functionCalls.modifyLast{
                                $0.arguments += partial
                            }}
                        }
                    default: ()
                    }
                }
            }

            src.addEventListener("content_block_stop") { id, event, data in
//                print("[CS] content_block_stop: \(data ?? "")")
                // No need to handle
            }

            src.addEventListener("message_delta") { id, event, data in
//                print("[CS] message_delta: \(data ?? "")")
                // No need to handle; we don't care about any of the properties returned here, like stop_reason or usage
            }

            src.addEventListener("message_stop") { id, event, data in
//                print("[CS] message_stop: \(data ?? "")")
                // No need to handle
            }

            src.onComplete { statusCode, reconnect, error in
                if let statusCode, statusCode / 100 == 2 {
                    if options.printToConsole {
                        let allMessages = messages.map(\.content).joined(separator: "\n[Next message]\n")
                        print("[ChatLLM] Response:\n\(allMessages)")
                    }
                    continuation.finish()
                } else {
                    if let error {
                        continuation.finish(throwing: error as Error)
                    } else if let statusCode {
                        continuation.finish(throwing: LLMError.http(statusCode))
                    } else {
                        continuation.finish(throwing: LLMError.unknown(nil))
                    }
                }
            }
            src.connect()
        }
    }
    // MARK: - Helpers

    private func createRequest(prompt: [LLMMessage], stream: Bool, functions: [LLMFunction]) throws -> URLRequest {
        let (system, messages) = try prompt.convertToAnthropicPrompt()
        var payload = Request(
            messages: messages,
            system: system,
            model: options.model.modelId,
            max_tokens: options.maxTokens,
            stop_sequences: options.stopSequences.nilIfEmptyArray,
            temperature: options.temperature,
            stream: stream,
            tools: functions.map(\.asClaudeTool)
        )
        if let prefix = options.responsePrefix.nilIfEmpty {
            payload.messages.append(.init(role: .assistant, content: [.init(type: .text, text: prefix)]))
        }
        if options.printToConsole {
            print("[ChatLLM] System: \(system ?? "none")\n\(messages)")
        }

        let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = try! JSONEncoder().encode(payload)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(credentials.apiKey, forHTTPHeaderField: "X-API-Key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        return urlRequest
    }
}

extension Array where Element == LLMMessage {
    func convertToAnthropicPrompt() throws -> (system: String?, messages: [ClaudeMessage]) {
        var system: String?
        var messages = [ClaudeMessage]()
        for (i, message) in self.enumerated() {
            // Extract top system message
            if message.role == .system, i == 0, self.count > 1 && self[1].role == .user {
                system = message.content
                continue
            }
            messages.append(try message.claudeMessage())
        }
        messages = messages.filter { !$0.isEmpty }
        return (system, messages: mergeContiguousMessagesWithSameRoles(messages: messages))
    }
}

private func mergeContiguousMessagesWithSameRoles(messages: [ClaudeMessage]) -> [ClaudeMessage] {
    var merged = [ClaudeMessage]()
    for message in messages {
        if let last = merged.last, last.role == message.role {
            merged[merged.count - 1] = .init(role: message.role, content: last.content + message.content)
        } else {
            merged.append(message)
        }
    }
    return merged
}

enum ClaudeMessageError: Error {
    case imageIsNotBase64URL
}

extension LLMMessage {
    func claudeMessage() throws -> ClaudeMessage {
        var m = ClaudeMessage(role: role.claudeRole, content: [])
        for image in images {
            guard let claudeImage = image.url.asClaudeImage else {
                throw ClaudeMessageError.imageIsNotBase64URL
            }
            m.content.append(claudeImage)
        }
        for call in functionCalls {
            m.content.append(.init(type: .tool_use, id: call.id, name: call.name, input: call.argumentsAsAnyCodable))
        }
        for resp in functionResponses {
            m.content.append(.init(type: .tool_result, tool_use_id: resp.id, content: resp.text))
        }
        // If no images, or text is non-empty, add the text block
        if m.content.isEmpty || content.nilIfEmpty != nil {
            m.content.append(.init(type: .text, text: content))
        }
        return m
    }
}

private extension URL {
    // Extract b64 url like `data:image/jpeg;base64,XXXX"
    // into ClaudeMessage.Content.Source

    var asClaudeImage: ClaudeMessage.Content? {
        var str = absoluteString
        // Check for data prefix and remove
        guard str.hasPrefix("data:") else {
            return nil
        }
        str = String(str[str.index(str.startIndex, offsetBy: 5)...])
        // search for ;base64, in absoluteString
        guard let base64Index = str.range(of: ";base64,") else {
            return nil
        }
        // Extract media type
        let mediaType = String(str[str.startIndex..<base64Index.lowerBound])
        // Extract base64 data
        let base64 = String(str[base64Index.upperBound...])
        return .init(type: .image, text: nil, source: .init(type: "base64", media_type: mediaType, data: base64))
    }
}

enum ClaudeRole: String, Equatable, Codable {
    case user
    case assistant

    var asLLMRole: LLMMessage.Role {
        switch self {
        case .user: return .user
        case .assistant: return .assistant
        }
    }
}

extension LLMMessage.Role {
    var claudeRole: ClaudeRole {
        switch self {
        case .user, .system, .function:
            return .user
        case .assistant:
            return .assistant
        }
    }
}

struct ClaudeTool: Equatable, Encodable {
    var name: String
    var description: String
    var input_schema: LLMFunction.JsonSchema
}

extension LLMFunction {
    var asClaudeTool: ClaudeTool {
        .init(name: name, description: description, input_schema: parameters)
    }
}

struct ClaudeMessage: Equatable, Codable {
    var role: ClaudeRole
    var content: [Content]

    /*
     {
                         "type": "tool_use",
                         "id": "toolu_01A09q90qw90lq917835lq9",
                         "name": "get_weather",
                         "input": {
                             "location": "San Francisco, CA",
                             "unit": "celsius"
                         }
                     }
     */

    struct Content: Equatable, Codable {
        /*
         {
           "type": "image",
           "source": {
             "type": "base64",
             "media_type": "image/jpeg",
             "data": "/9j/4AAQSkZJRg...",
           }
         },
         {"type": "text", "text": "What is in this image?"}
         */

        enum ContentType: String, Equatable, Codable {
            case text
            case image
            case tool_use
            case tool_result
        }

        var type: ContentType
        var text: String? // For type = text
        var source: Source? // For type = image
        var id: String? // For type = tool_use
        var name: String? // For type=tool_use
        var input: AnyCodable? // For type=tool_use
        var tool_use_id: String? // For type=tool_result
        var content: String? // For type=tool_result

        struct Source: Equatable, Codable {
            var type: String
            var media_type: String
            var data: String // base64
        }

        var asFunctionCall: LLMMessage.FunctionCall? {
            if type == .tool_use, let id, let name {
                return LLMMessage.FunctionCall(id: id, name: name, arguments: input?.jsonString ?? "{}")
            }
            return nil
        }
    }

    // Empty messages must be removed
    var isEmpty: Bool {
        for content in content {
            switch content.type {
            case .image:
                if content.source != nil {
                    return false
                }
            case .text:
                if content.text?.nilIfEmpty != nil {
                    return false
                }
            case .tool_use:
                if content.id != nil {
                    return false
                }
            case .tool_result:
                if content.content != nil {
                    return false
                }
            }
        }
        return true
    }
}

