import Foundation

public struct ChatGPT {
    public enum Model: String, Codable {
        case gpt35_turbo = "gpt-3.5-turbo"
        case gpt4 = "gpt-4"
        case gpt4_32k = "gpt-4-32k"
    }

    public struct Options: Equatable, Codable {
        public var temperature: Double
        public var max_tokens: Int
        public var model: Model
        public var stop: [String]
        public var printToConsole: Bool

        public init(temp: Double = 0.2, maxTokens: Int = 1000, model: Model = .gpt35_turbo, stop: [String] = [], printToConsole: Bool = false) {
            self.temperature = temp
            self.max_tokens = maxTokens
            self.model = model
            self.stop = stop
            self.printToConsole = printToConsole
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

    public var tokenLimit: Int {
        switch options.model {
        case .gpt35_turbo: return 4096
        case .gpt4: return 8192
        case .gpt4_32k: return 32768
        }
    }

    public func completeStreaming(prompt: [LLMMessage]) -> AsyncThrowingStream<LLMMessage, Error> {
     let cr = ChatCompletionRequest(messages: prompt.map { $0.asChatGPT }, model: options.model.rawValue, temperature: options.temperature, stop: options.stop.nilIfEmptyArray)
       let request = createChatRequest(completionRequest: cr)

        if options.printToConsole {
            print("OpenAI request:\n\((prompt.asConversationString))")
        }

       return AsyncThrowingStream { continuation in
           let src = EventSource(urlRequest: request)

           var message = Message(role: .assistant, content: "")

           src.onComplete { statusCode, reconnect, error in
               if let statusCode, statusCode / 100 == 2 {
                   if options.printToConsole {
                       print("OpenAI response:\n\((message.content))")
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

   private func createChatRequest(completionRequest: ChatCompletionRequest) -> URLRequest {
       let url = URL(string: "https://api.openai.com/v1/chat/completions")!
       var request = URLRequest(url: url)
       request.httpMethod = "POST"
       request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
       request.setValue("application/json", forHTTPHeaderField: "Content-Type")
       if let orgId = credentials.orgId {
           request.setValue(orgId, forHTTPHeaderField: "OpenAI-Organization")
       }
       request.httpBody = try! JSONEncoder().encode(completionRequest)
       return request
   }

}

private extension LLMMessage {
    var asChatGPT: ChatGPT.Message {
        ChatGPT.Message(role: role.asChatGPT, content: content)
    }
}

private extension LLMMessage.Role {
    var asChatGPT: ChatGPT.Message.Role {
        switch self {
        case .assistant: return .assistant
        case .system: return .system
        case .user: return .user
        }
    }
}

private extension ChatGPT.Message {
    var asLLMMessage: LLMMessage {
        LLMMessage(role: role.asLLMMessage, content: content)
    }
}

private extension ChatGPT.Message.Role {
    var asLLMMessage: LLMMessage.Role {
        switch self {
        case .assistant: return .assistant
        case .system: return .system
        case .user: return .user
        }
    }
}

//import Foundation
//
//extension OpenAIAPI {
//    public struct Message: Equatable, Codable, Hashable {
//        public enum Role: String, Equatable, Codable, Hashable {
//            case system
//            case user
//            case assistant
//        }

//        public var role: Role
//        public var content: String

//        public init(role: Role, content: String) {
//            self.role = role
//            self.content = content
//        }
//    }

//    public struct ChatCompletionRequest: Codable {
//        var messages: [Message]
//        var model: String
//        var max_tokens: Int = 1500
//        var temperature: Double = 0.2
//        var stream = false
//        var stop: [String]?

//        public init(messages: [Message], model: String = "gpt-3.5-turbo", max_tokens: Int = 1500, temperature: Double = 0.2, stop: [String]? = nil) {
//            self.messages = messages
//            self.model = model
//            self.max_tokens = max_tokens
//            self.temperature = temperature
//            self.stop = stop
//        }
//    }
//
//    // MARK: - Plain completion
//
//    struct ChatCompletionResponse: Codable {
//        struct Choice: Codable {
//            var message: Message
//        }
//        var choices: [Choice]
//    }
//
//    public func completeChat(_ completionRequest: ChatCompletionRequest) async throws -> String {
//        let request = try createChatRequest(completionRequest: completionRequest)
//        let (data, response) = try await URLSession.shared.data(for: request)
//        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
//            throw Errors.invalidResponse(String(data: data, encoding: .utf8) ?? "<failed to decode response>")
//        }
//        let completionResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
//        guard completionResponse.choices.count > 0 else {
//            throw Errors.noChoices
//        }
//        return completionResponse.choices[0].message.content
//    }
//
//    // MARK: - Streaming completion
//
//    public func completeChatStreaming(_ completionRequest: ChatCompletionRequest) throws -> AsyncStream<Message> {
//        var cr = completionRequest
//        cr.stream = true
//        let request = try createChatRequest(completionRequest: cr)
//
//        return AsyncStream { continuation in
//            let src = EventSource(urlRequest: request)
//
//            var message = Message(role: .assistant, content: "")
//
//            src.onComplete { statusCode, reconnect, error in
//                continuation.finish()
//            }
//            src.onMessage { id, event, data in
//                guard let data, data != "[DONE]" else { return }
//                do {
//                    let decoded = try JSONDecoder().decode(ChatCompletionStreamingResponse.self, from: Data(data.utf8))
//                    if let delta = decoded.choices.first?.delta {
//                        message.role = delta.role ?? message.role
//                        message.content += delta.content ?? ""
//                        continuation.yield(message)
//                    }
//                } catch {
//                    print("Chat completion error: \(error)")
//                }
//            }
//            src.connect()
//        }
//    }
//
//    public func completeChatStreamingWithObservableObject(_ completionRequest: ChatCompletionRequest) throws -> StreamingCompletion {
//        let completion = StreamingCompletion()
//        Task {
//            do {
//                for await message in try self.completeChatStreaming(completionRequest) {
//                    DispatchQueue.main.async {
//                        completion.text = message.content
//                    }
//                }
//                DispatchQueue.main.async {
//                    completion.status = .complete
//                }
//            } catch {
//                DispatchQueue.main.async {
//                    completion.status = .error
//                }
//            }
//        }
//        return completion
//    }
//
//
//}
