import Foundation

public extension URL {
    static var groqOpenAIChatEndpoint: URL {
        URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    }

    static var openRouterOpenAIChatEndpoint: URL {
        URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    }
}

public struct ChatGPT {
    public enum Model: Equatable, Codable {
        case gpt35_turbo
        case gpt35_turbo_0125
        case gpt35_turbo_16k
        case gpt4
        case gpt4_turbo_preview
        case gpt4_turbo // includes vision
        case gpt4_omni
        case gpt4_32k
        case gpt4_vision_preview
        case custom(String, Int)

        var name: String {
            switch self {
            case .gpt35_turbo:
                return "gpt-3.5-turbo"
            case .gpt35_turbo_16k:
                return "gpt-3.5-turbo-16k"
            case .gpt35_turbo_0125:
                return "gpt-3.5-turbo-0125"
            case .gpt4_omni:
                return "gpt-4o"
            case .custom(let string, _):
                return string
            case .gpt4:
                return "gpt-4"
            case .gpt4_turbo: return "gpt-4-turbo"
            case .gpt4_turbo_preview: return "gpt-4-turbo-preview"
            case .gpt4_32k:
                return "gpt-4-32k"
            case .gpt4_vision_preview: return "gpt-4-vision-preview"
            }
        }

        var tokenLimit: Int {
            switch self {
            case .gpt35_turbo: return 4096
            case .gpt35_turbo_16k, .gpt35_turbo_0125: return 16384
            case .gpt4: return 8192
            case .gpt4_32k: return 32768
            case .gpt4_turbo_preview, .gpt4_turbo, .gpt4_vision_preview, .gpt4_omni: return 128_000
            case .custom(_, let limit): return limit
            }
        }
    }

    public struct Options: Equatable, Codable {
        public var temperature: Double
        public var max_tokens: Int?
        public var model: Model
        public var stop: [String]
        public var printToConsole: Bool

        // `printCost` disables streaming and prints cost to the console
        public var printCost: Bool
        public var jsonMode: Bool
        public var baseURL: URL // Use to call OpenAI-compatible models that are not actually OpenAI's

        public init(temp: Double = 0, model: Model = .gpt35_turbo, maxTokens: Int? = nil, stop: [String] = [], printToConsole: Bool = false, printCost: Bool = false, jsonMode: Bool = false, baseURL: URL = URL(string: "https://api.openai.com/v1/chat/completions")!) {
            self.temperature = temp
            self.model = model
            self.max_tokens = maxTokens
            self.stop = stop
            self.printToConsole = printToConsole
            self.printCost = printCost
            self.jsonMode = jsonMode
            self.baseURL = baseURL
        }
    }

    public var credentials: OpenAICredentials
    public var options: Options

    public init(credentials: OpenAICredentials, options: Options = Options()) {
        self.credentials = credentials
        self.options = options
    }
}

extension ChatGPT: ChatLLM {
    struct Message: Equatable, Codable, Hashable {
       enum Role: String, Equatable, Codable, Hashable {
           case system
           case user
           case assistant
           case function
       }

        struct Content: Equatable, Codable, Hashable {
            enum ContentType: String, Equatable, Codable, Hashable {
                case text = "text"
                case imageURL = "image_url"
            }
            struct ImageURL: Equatable, Codable, Hashable {
                var url: String
                var detail: LLMMessage.Image.Detail?
            }
            var type: ContentType
            var text: String?
            var image_url: ImageURL?

            static func text(_ str: String) -> Content {
                .init(type: .text, text: str)
            }

            static func image(url: String, detail: LLMMessage.Image.Detail) -> Content {
                .init(type: .imageURL, image_url: .init(url: url, detail: detail))
            }
        }

        var role: Role
        var content: [Content] // Decode either a string or an array. When encoding, encode as string if possible.
        var name: String? // For function call responses (role=function)
        var function_call: LLMMessage.FunctionCall?
        
        var contentAsText: String {
            content.compactMap { $0.text }.joined()
        }

        init(role: Role, content: [Content], functionCall: LLMMessage.FunctionCall? = nil, nameOfFunctionThatProduced: String? = nil) {
            self.role = role
            self.content = content
            self.function_call = functionCall
            self.name = nameOfFunctionThatProduced
        }

        // MARK: - Encoding/Decoding

        enum CodingKeys: String, CodingKey {
            case role
            case content
            case name
            case function_call
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            role = try container.decode(Role.self, forKey: .role)
            if let contentStr = try? container.decode(String.self, forKey: .content) {
                self.content = [.text(contentStr)]
            } else if let contentArray = try? container.decode([Content].self, forKey: .content) {
                self.content = contentArray
            } else {
                self.content = []
            }
            name = try container.decodeIfPresent(String.self, forKey: .name)
            function_call = try container.decodeIfPresent(LLMMessage.FunctionCall.self, forKey: .function_call)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(role, forKey: .role)
            if content.count == 1, let text = content.first?.text {
                try container.encode(text, forKey: .content)
            } else {
                try container.encode(content, forKey: .content)
            }
            try container.encodeIfPresent(name, forKey: .name)
            try container.encodeIfPresent(function_call, forKey: .function_call)
        }
   }

   struct ChatCompletionRequest: Encodable {
       var messages: [Message]
       var model: String
       var temperature: Double = 0.2
       var stream = true
       var stop: [String]?
       var functions: [LLMFunction]?
       var response_format: ResponseFormat?
       var max_tokens: Int?
       var logprobs: Bool?
       var n: Int?

       struct ResponseFormat: Codable {
           var type: String  = "text"
       }
   }

    private struct ChatCompletionStreamingResponse: Codable {
        struct Choice: Codable {
            struct MessageDelta: Codable {
                var role: Message.Role?
                var content: String?
                var function_call: PartialFunctionCall?

                struct PartialFunctionCall: Codable {
                    var name: String?
                    var arguments: String?
                }
            }
            var delta: MessageDelta
        }

        var choices: [Choice]
    }

    public func completeStreaming(prompt: [LLMMessage]) -> AsyncThrowingStream<LLMMessage, Error> {
        _completeStreaming(prompt: prompt, functions: [])
    }

    public var tokenLimit: Int {
        options.model.tokenLimit
    }

    public func completeStreamingWithJsonHint(prompt: [LLMMessage]) -> AsyncThrowingStream<LLMMessage, Error> {
        var model = self
        // TODO: Re-enable auto json mode
//        model.options.jsonMode = true
        return model.completeStreaming(prompt: prompt)
    }

    func _completeStreaming(prompt: [LLMMessage], functions: [LLMFunction]) -> AsyncThrowingStream<LLMMessage, Error> {
        // `printCost` requires not streaming the response.
        if options.printCost {
            return AsyncThrowingStream { cont in
                Task {
                    do {
                        let result = try await _complete(prompt: prompt, functions: functions)
                        cont.yield(result)
                        cont.finish()
                    } catch {
                        cont.finish(throwing: error)
                    }
                }
            }
        }

        let request = createChatRequest(prompt: prompt, functions: functions, stream: true)

        if options.printToConsole {
            print("OpenAI request:\n\((prompt.asConversationString))")
        }

       return AsyncThrowingStream { continuation in
           let src = EventSource(urlRequest: request)

           var message = Message(role: .assistant, content: [.text("")])

           src.onComplete { statusCode, reconnect, error in
               if let statusCode, statusCode / 100 == 2 {
                   if options.printToConsole {
                       print("OpenAI response:\n\(message.contentAsText)")
                   }
                   continuation.finish()
               } else {
                   if let error {
                       continuation.yield(with: .failure(error))
                   } else if let statusCode {
                       continuation.yield(with: .failure(LLMError.http(statusCode)))
                   } else {
                       continuation.yield(with: .failure(LLMError.unknown(nil)))
                   }
               }
           }
           src.onMessage { id, event, data in
               guard let data, data != "[DONE]" else { return }
//               print(data)
               do {
                   let decoded = try JSONDecoder().decode(ChatCompletionStreamingResponse.self, from: Data(data.utf8))
                   if let delta = decoded.choices.first?.delta {
                       message.role = delta.role ?? message.role
                       message.content = [.text(message.contentAsText + (delta.content ?? ""))]
                       if let functionDelta = delta.function_call {
                           message.function_call = message.function_call ?? .init(name: "", arguments: "")
                           message.function_call?.name += functionDelta.name ?? ""
                           message.function_call?.arguments += functionDelta.arguments ?? ""
                       }
                       continuation.yield(message.asLLMMessage)
                   }
               } catch {
                   print("Chat completion error: \(error)")
                   continuation.yield(with: .failure(error))
               }
           }
           src.connect()
       }
    }

    private func decodeChatStreamingResponse(jsonStr: String) -> String? {
       guard let json = try? JSONDecoder().decode(ChatCompletionStreamingResponse.self, from: Data(jsonStr.utf8)) else {
           return nil
       }
       return json.choices.first?.delta.content
   }

    func createChatRequest(prompt: [LLMMessage], functions: [LLMFunction], stream: Bool, n: Int? = nil, logProbs: Bool = false) -> URLRequest {
        let cr = ChatCompletionRequest(
            messages: prompt.map { $0.asChatGPT },
            model: options.model.name,
            temperature: options.temperature,
            stream: stream,
            stop: options.stop.nilIfEmptyArray,
            functions: functions.nilIfEmptyArray,
            response_format: options.jsonMode ? .init(type: "json_object") : nil,
            max_tokens: options.max_tokens,
            logprobs: logProbs ? true : nil,
            n: n
        )

       var request = URLRequest(url: options.baseURL)
       request.httpMethod = "POST"
       request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
       request.setValue("application/json", forHTTPHeaderField: "Content-Type")
       if let orgId = credentials.orgId {
           request.setValue(orgId, forHTTPHeaderField: "OpenAI-Organization")
       }
       request.httpBody = try! JSONEncoder().encode(cr)
       return request
   }
}

private extension LLMMessage {
    var asChatGPT: ChatGPT.Message {
        var msg = ChatGPT.Message(role: role.asChatGPT, content: [], functionCall: functionCall, nameOfFunctionThatProduced: nameOfFunctionThatProduced)
        for image in images {
            msg.content.append(.image(url: image.url.absoluteString, detail: image.detail ?? .auto))
        }
        if msg.content.count == 0 || self.content.nilIfEmpty != nil {
            msg.content.append(.text(self.content))
        }
        return msg
    }
}

private extension LLMMessage.Role {
    var asChatGPT: ChatGPT.Message.Role {
        switch self {
        case .assistant: return .assistant
        case .system: return .system
        case .user: return .user
        case .function: return .function
        }
    }
}

extension ChatGPT.Message {
    var asLLMMessage: LLMMessage {
        LLMMessage(role: role.asLLMMessage, content: contentAsText, functionCall: function_call, nameOfFunctionThatProduced: name)
    }
}

private extension ChatGPT.Message.Role {
    var asLLMMessage: LLMMessage.Role {
        switch self {
        case .assistant: return .assistant
        case .system: return .system
        case .user: return .user
        case .function: return .function
        }
    }
}

extension ChatGPT: FunctionCallingLLM {
    public func complete(prompt: [LLMMessage], functions: [LLMFunction]) async throws -> LLMMessage {
        try await _complete(prompt: prompt, functions: functions)
    }

    public func completeStreaming(prompt: [LLMMessage], functions: [LLMFunction]) -> AsyncThrowingStream<LLMMessage, Error> {
        _completeStreaming(prompt: prompt, functions: functions)
    }
}
