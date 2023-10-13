import Foundation

public struct ChatGPT {
    public enum Model: String, Codable {
        case gpt35_turbo = "gpt-3.5-turbo"
        case gpt35_turbo_16k = "gpt-3.5-turbo-16k"
        case gpt4 = "gpt-4"
        case gpt4_32k = "gpt-4-32k"
        case gpt_35_ft_tabOrg = "ft:gpt-3.5-turbo-0613:the-browser-company::7r6Y87Hk" // do not commit
    }

    public struct Options: Equatable, Codable {
        public var temperature: Double
//        public var max_tokens: Int
        public var model: Model
        public var stop: [String]
        public var printToConsole: Bool

        // `printCost` disables streaming and prints cost to the console
        public var printCost: Bool

        public init(temp: Double = 0.2, model: Model = .gpt35_turbo, stop: [String] = [], printToConsole: Bool = false, printCost: Bool = false) {
            self.temperature = temp
            self.model = model
            self.stop = stop
            self.printToConsole = printToConsole
            self.printCost = printCost
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
        var role: Role
        var content: String?
        var name: String? // For function call responses (role=function)
        var function_call: LLMMessage.FunctionCall?
   }

   struct ChatCompletionRequest: Encodable {
       var messages: [Message]
       var model: String
       var temperature: Double = 0.2
       var stream = true
       var stop: [String]?
       var functions: [LLMFunction]?
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

    public var tokenLimit: Int {
        switch options.model {
        case .gpt35_turbo, .gpt_35_ft_tabOrg: return 4096
        case .gpt35_turbo_16k: return 16384
        case .gpt4: return 8192
        case .gpt4_32k: return 32768
        }
    }

    public func completeStreaming(prompt: [LLMMessage]) -> AsyncThrowingStream<LLMMessage, Error> {
        _completeStreaming(prompt: prompt, functions: [])
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

           var message = Message(role: .assistant, content: "")

           src.onComplete { statusCode, reconnect, error in
               if let statusCode, statusCode / 100 == 2 {
                   if options.printToConsole {
                       print("OpenAI response:\n\((message.content ?? ""))")
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
                       message.content = (message.content ?? "") + (delta.content ?? "")
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

    // don't pass functions AND stream
    private func createChatRequest(prompt: [LLMMessage], functions: [LLMFunction], stream: Bool) -> URLRequest {
        let cr = ChatCompletionRequest(messages: prompt.map { $0.asChatGPT }, model: options.model.rawValue, temperature: options.temperature, stream: stream, stop: options.stop.nilIfEmptyArray, functions: functions.nilIfEmptyArray)

       let url = URL(string: "https://api.openai.com/v1/chat/completions")!
       var request = URLRequest(url: url)
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
        ChatGPT.Message(role: role.asChatGPT, content: content, name: nameOfFunctionThatProduced, function_call: functionCall)
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

private extension ChatGPT.Message {
    var asLLMMessage: LLMMessage {
        LLMMessage(role: role.asLLMMessage, content: content ?? "", functionCall: function_call, nameOfFunctionThatProduced: name)
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

extension ChatGPT {
    private struct NonStreamingResponse: Codable {
        struct Choice: Codable {
            var message: ChatGPT.Message
        }

        struct Usage: Codable {
            var completion_tokens: Int
            var prompt_tokens: Int
        }

        var choices: [Choice]
        var usage: Usage?
    }

    func _complete(prompt: [LLMMessage], functions: [LLMFunction] = []) async throws -> LLMMessage {
        let request = createChatRequest(prompt: prompt, functions: functions, stream: false)
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(NonStreamingResponse.self, from: data)

        guard let result = response.choices.first?.message else {
            throw LLMError.unknown
        }

        if options.printToConsole {
            print("OpenAI response:\n\((result))")
        }

        if options.printCost, let usage = response.usage {
            let cost = options.model.cost
            let promptCents = Double(usage.prompt_tokens) / 1000 * cost.centsPer1kPromptToken
            let completionCents = Double(usage.completion_tokens) / 1000 * cost.centsPer1kCompletionToken
            let totalCents = promptCents + completionCents
            func formatCents(_ cents: Double) -> String {
                let formatter = NumberFormatter()
                formatter.numberStyle = .currency
                formatter.currencyCode = "USD"
                formatter.currencySymbol = "$"
                formatter.maximumFractionDigits = 2
                return formatter.string(from: NSNumber(value: cents / 100))!
            }

            print(
            """
            1000 copies of this \(options.model) request would cost, as of July 14, 2023:
               \(formatCents(promptCents * 1000)): \(usage.prompt_tokens) prompt tokens per request
             + \(formatCents(completionCents * 1000)): \(usage.completion_tokens) completion tokens per request
            --------------------
             = \(formatCents(totalCents * 1000)): total
            """)
        }

        return result.asLLMMessage
    }
}

extension ChatGPT.Model {
    var cost: (centsPer1kPromptToken: Double, centsPer1kCompletionToken: Double) {
        switch self {
        case .gpt35_turbo: return (0.15, 0.2)
        case .gpt35_turbo_16k: return (0.3, 0.4)
        case .gpt_35_ft_tabOrg: return (1.2, 1.6)
        case .gpt4: return (3, 6)
        case .gpt4_32k: return (6, 12)
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
