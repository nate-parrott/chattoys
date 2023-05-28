import Foundation

public struct AnthropicCredentials {
    var apiKey: String
    var orgId: String?

    public init(apiKey: String) {
        self.apiKey = apiKey
    }
}

public struct Claude {
    public enum Model: String, Equatable {
        case claudeV1 = "claude-v1"
        case claudeV1_100k = "claude-v1-100k"
        case claudeInstantV1 = "claude-instant-v1"
        case claudeInstantV1_100k = "claude-instant-v1-100k"
    }

    public struct Options {
        public var model: Model
        public var maxTokens: Int
        public var stopSequences: [String]
        public var temperature: Double

        public init(model: Model = .claudeInstantV1, maxTokens: Int = 1000, stopSequences: [String] = [], temperature: Double = 0.5) {
            self.model = model
            self.maxTokens = maxTokens
            self.stopSequences = stopSequences
            self.temperature = temperature
        }
    }

    public var credentials: AnthropicCredentials
    public var options: Options

    public init(credentials: AnthropicCredentials, options: Options = Options()) {
        self.credentials = credentials
        self.options = options
    }
}

extension Claude: ChatLLM {
    private struct Request: Codable {
        var prompt: String
        var model: String
        var max_tokens_to_sample: Int
        var stop_sequences: [String]?
        var temperature: Double
        var stream: Bool
    }

    private struct Response: Codable {
        var completion: String
    }

    public func completeStreaming(prompt: [LLMMessage]) -> AsyncThrowingStream<LLMMessage, Error> {
        let payload = Request(
            prompt: prompt.asAnthropicPrompt,
             model: options.model.rawValue, 
             max_tokens_to_sample: options.maxTokens, 
             stop_sequences: options.stopSequences.nilIfEmptyArray, 
             temperature: options.temperature,
            stream: true
        )
       return AsyncThrowingStream { continuation in
//            Task {
//                do {
//                    let endpoint = URL(string: "https://api.anthropic.com/v1/complete")!
//                    var urlRequest = URLRequest(url: endpoint)
//                    urlRequest.httpMethod = "POST"
//                    urlRequest.httpBody = try! JSONEncoder().encode(payload)
//                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
//                    urlRequest.setValue(credentials.apiKey, forHTTPHeaderField: "X-API-Key")
//
//                    let (data, _) = try await URLSession.shared.data(for: urlRequest)
//                    // print response as string
//                    print(String(data: data, encoding: .utf8)!)
//                    let response = try JSONDecoder().decode(Response.self, from: data)
//                    continuation.yield(LLMMessage(role: .assistant, content: response.completion))
//                    continuation.finish()
//                } catch {
//                    continuation.yield(with: .failure(error))
//                }
//            }

           let endpoint = URL(string: "https://api.anthropic.com/v1/complete")!
           var urlRequest = URLRequest(url: endpoint)
           urlRequest.httpMethod = "POST"
           urlRequest.httpBody = try! JSONEncoder().encode(payload)
           urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
           urlRequest.setValue(credentials.apiKey, forHTTPHeaderField: "X-API-Key")

            let src = EventSource(urlRequest: urlRequest)

            var message = LLMMessage(role: .assistant, content: "")

            src.onComplete { statusCode, reconnect, error in
                if let statusCode, statusCode / 100 == 2 {
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
                    let decoded = try JSONDecoder().decode(Response.self, from: Data(data.utf8))
                    message.content = decoded.completion
                    continuation.yield(message)
//                    if let delta = decoded.choices.first?.delta {
//                        message.role = delta.role ?? message.role
//                        message.content += delta.content ?? ""
//                        continuation.yield(message.asLLMMessage)
//                    }
                } catch {
                    print("Chat completion error: \(error)")
                    continuation.yield(with: .failure(error))
                }
            }
            src.connect()
       }
    }
}

extension Sequence where Element == LLMMessage {
    var asAnthropicPrompt: String {
        var lines = self.map { "\($0.role.asAnthropicRole): \($0.content)" }
        lines.append("Assistant: ")
        return lines.joined(separator: "\n\n")
    }
}

private extension LLMMessage.Role {
    var asAnthropicRole: String {
        switch self {
        case .user, .system: return "Human"
        case .assistant: return "Assistant"
        }
    }
}
