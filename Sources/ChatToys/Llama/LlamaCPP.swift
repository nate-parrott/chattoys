import Foundation

// Install and run this: https://github.com/abetlen/llama-cpp-python#web-server

public struct LlamaCPP {
    public struct Options: Equatable, Codable {
        public var temperature: Double
        public var max_tokens: Int
        public var stop: [String]
        public var printToConsole: Bool

        // `printCost` disables streaming and prints cost to the console
        public var printCost: Bool

        public init(temp: Double = 0.2, maxTokens: Int = 1000, stop: [String] = [], printToConsole: Bool = false, printCost: Bool = false) {
            self.temperature = temp
            self.max_tokens = maxTokens
            self.stop = stop
            self.printToConsole = printToConsole
            self.printCost = printCost
        }
    }

    public var baseURL: URL
    public var tokenLimit: Int
    public var modelName: String
    public var options: Options

    public init(modelName: String = "", tokenLimit: Int = 2048, baseURL: URL = URL(string: "http://localhost:8000")!, options: Options = Options()) {
        self.modelName = modelName
        self.tokenLimit = tokenLimit
        self.baseURL = baseURL
        self.options = options
    }
}

extension LlamaCPP: ChatLLM {
    struct Message: Equatable, Codable, Hashable {
       enum Role: String, Equatable, Codable, Hashable {
           case system
           case user
           case assistant
       }
        var role: Role
        var content: String
   }

   struct ChatCompletionRequest: Codable {
       var messages: [Message]
       var model: String
       var temperature: Double = 0.2
       var stream = true
       var stop: [String]?
       var max_tokens: Int = 2048
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

    public func completeStreaming(prompt: [LLMMessage]) -> AsyncThrowingStream<LLMMessage, Error> {
        let request = createChatRequest(prompt: prompt, stream: true)

        if options.printToConsole {
            print("Llama request:\n\((prompt.asConversationString))")
        }

       return AsyncThrowingStream { continuation in
           let src = EventSource(urlRequest: request)

           var message = Message(role: .assistant, content: "")

           src.onComplete { statusCode, reconnect, error in
               if let statusCode, statusCode / 100 == 2 {
                   if options.printToConsole {
                       print("Llama response:\n\((message.content))")
                   }
                   continuation.finish()
               } else {
                   if let error {
                       continuation.yield(with: .failure(error))
                   } else if let statusCode {
                       continuation.yield(with: .failure(LLMError.http(statusCode)))
                   } else {
                       continuation.yield(with: .failure(LLMError.unknown))
                   }
               }
           }
           src.onMessage { id, event, data in
               guard let data, data != "[DONE]" else { return }
               do {
                   let decoded = try JSONDecoder().decode(ChatCompletionStreamingResponse.self, from: Data(data.utf8))
                   if let delta = decoded.choices.first?.delta {
                       message.role = delta.role ?? message.role
                       message.content += delta.content ?? ""
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

    private func createChatRequest(prompt: [LLMMessage], stream: Bool) -> URLRequest {
        let cr = ChatCompletionRequest(messages: prompt.map { $0.asLlama }, model: modelName, temperature: options.temperature, stream: stream, stop: options.stop.nilIfEmptyArray, max_tokens: options.max_tokens)

       let url = URL(string: "/v1/chat/completions", relativeTo: baseURL)!
       var request = URLRequest(url: url)
       request.httpMethod = "POST"
       request.setValue("application/json", forHTTPHeaderField: "Content-Type")
       request.httpBody = try! JSONEncoder().encode(cr)
       return request
   }

}

private extension LLMMessage {
    var asLlama: LlamaCPP.Message {
        LlamaCPP.Message(role: role.asLlama, content: content)
    }
}

private extension LLMMessage.Role {
    var asLlama: LlamaCPP.Message.Role {
        switch self {
        case .assistant: return .assistant
        case .system: return .system
        case .user: return .user
        }
    }
}

private extension LlamaCPP.Message {
    var asLLMMessage: LLMMessage {
        LLMMessage(role: role.asLLMMessage, content: content)
    }
}

private extension LlamaCPP.Message.Role {
    var asLLMMessage: LLMMessage.Role {
        switch self {
        case .assistant: return .assistant
        case .system: return .system
        case .user: return .user
        }
    }
}

extension LlamaCPP {
    private struct NonStreamingResponse: Codable {
        struct Choice: Codable {
            var message: LlamaCPP.Message
        }

        var choices: [Choice]
    }

    func complete(prompt: [LLMMessage]) async throws -> LLMMessage {
        let request = createChatRequest(prompt: prompt, stream: false)
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(NonStreamingResponse.self, from: data)

        guard let result = response.choices.first?.message else {
            throw LLMError.unknown
        }

        return result.asLLMMessage
    }
}
