import Foundation

public struct PerplexityCredentials {
    var apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }
}

public struct PerplexityLLM: ChatLLM {
    public struct Options: Equatable {
        // https://docs.perplexity.ai/docs/model-cards
        public enum Model: String {
            case pplx7b = "pplx-7b-chat"
            case pplx70b = "pplx-70b-chat"
            case pplx7bOnline = "pplx-7b-online"
            case pplx70bOnline = "pplx-70b-online"
            case llama270b = "llama-2-70b-chat"

            public var contextLength: Int {
                switch self {
                case .pplx7b: return 8196
                case .pplx70b, .pplx7bOnline, .pplx70bOnline, .llama270b: return 4096
                }
            }
        }
        public var model: Options.Model
        public var max_tokens: Int?
        public var temperature: Double?

        public init(model: Model, max_tokens: Int? = nil, temperature: Double? = nil) {
            self.model = model
            self.max_tokens = max_tokens
            self.temperature = temperature
        }
    }

    public var credentials: PerplexityCredentials
    public var options: Options

    public init(credentials: PerplexityCredentials, options: Options) {
        self.credentials = credentials
        self.options = options
    }

    // MARK: - ChatLLM

    public func completeStreaming(prompt: [LLMMessage]) -> AsyncThrowingStream<LLMMessage, Error> {
        let request = createChatRequest(prompt: prompt)

       return AsyncThrowingStream { continuation in
           let src = EventSource(urlRequest: request)

           var message = Message(role: .assistant, content: "")

           src.onComplete { statusCode, reconnect, error in
               if let statusCode, statusCode / 100 == 2 {
//                   if options.printToConsole {
//                       print("OpenAI response:\n\((message.content ?? ""))")
//                   }
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
//               if let data {
//                   print("Data: \(data)")
//               }
               guard let data, data != "[DONE]" else { return }
               do {
                   let decoded = try JSONDecoder().decode(ChatCompletionStreamingResponse.self, from: Data(data.utf8))
                   if let delta = decoded.choices.first?.delta {
                       message.role = delta.role ?? message.role
                       message.content = (message.content ?? "") + (delta.content ?? "")
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
    
    public var tokenLimit: Int { options.model.contextLength }

    // MARK: - Impl

    private func createChatRequest(prompt: [LLMMessage]) -> URLRequest {
        let cr = ChatCompletionRequest(
            messages: prompt.map { $0.asPerplexity },
            model: options.model.rawValue,
            temperature: options.temperature,
            stream: true
        )

       let url = URL(string: "https://api.perplexity.ai/chat/completions")!
       var request = URLRequest(url: url)
       request.httpMethod = "POST"
       request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
       request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//       if let orgId = credentials.orgId {
//           request.setValue(orgId, forHTTPHeaderField: "OpenAI-Organization")
//       }
       request.httpBody = try! JSONEncoder().encode(cr)
       return request
   }

    struct Message: Equatable, Codable, Hashable {
       enum Role: String, Equatable, Codable, Hashable {
           case system
           case user
           case assistant
       }
        var role: Role
        var content: String?
   }

   struct ChatCompletionRequest: Encodable {
       var messages: [Message]
       var model: String
       var temperature: Double?
       var max_tokens: Int?
       var stream = true
   }

    private struct ChatCompletionStreamingResponse: Codable {
        struct Choice: Codable {
            struct MessageDelta: Codable {
                var role: Message.Role?
                var content: String?
            }
            var delta: MessageDelta
        }

        var choices: [Choice]
    }
}

private extension LLMMessage {
    var asPerplexity: PerplexityLLM.Message {
        PerplexityLLM.Message(role: role.asPerplexity, content: content)
    }
}

private extension LLMMessage.Role {
    var asPerplexity: PerplexityLLM.Message.Role {
        switch self {
        case .assistant: return .assistant
        case .system: return .system
        case .user: return .user
        case .function: fatalError("Can't pass a `function` message to a Perplexity LLM")
        }
    }
}

private extension PerplexityLLM.Message {
    var asLLMMessage: LLMMessage {
        LLMMessage(role: role.asLLMMessage, content: content ?? "")
    }
}

private extension PerplexityLLM.Message.Role {
    var asLLMMessage: LLMMessage.Role {
        switch self {
        case .assistant: return .assistant
        case .system: return .system
        case .user: return .user
        }
    }
}
