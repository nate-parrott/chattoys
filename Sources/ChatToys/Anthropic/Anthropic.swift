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
        case claudeInstant1 = "claude-instant-1"
        case claude2 = "claude-2"
        case claude3Sonnet = "claude-3-sonnet-20240229" // medium
    }

    public struct Options {
        public var model: Model
        public var maxTokens: Int
        public var stopSequences: [String]
        public var temperature: Double
        public var printToConsole: Bool
        public var responsePrefix: String // Forces the model to use this as the beginning of the response. (This prefix _will_ be included in the output).

        public init(model: Model = .claudeInstant1, maxTokens: Int = 1000, stopSequences: [String] = [], temperature: Double = 0.5, printToConsole: Bool = false, responsePrefix: String = "") {
            self.model = model
            self.maxTokens = maxTokens
            self.stopSequences = stopSequences
            self.temperature = temperature
            self.printToConsole = printToConsole
            self.responsePrefix = responsePrefix
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
        var messages: [ClaudeMessage]
        var system: String?
        var model: String
        var max_tokens: Int
        var stop_sequences: [String]?
        var temperature: Double
        var stream: Bool
    }

    private struct Response: Codable {
        var completion: String
    }

    public var tokenLimit: Int {
        switch options.model {
        case .claudeInstant1, .claude2: return 100_000
        case .claude3Sonnet: return 200_000
        }
    }


    public func completeStreaming(prompt: [LLMMessage]) -> AsyncThrowingStream<LLMMessage, Error> {
       return AsyncThrowingStream { continuation in
           let payload: Request
           do {
               let (system, messages) = try prompt.convertToAnthropicPrompt()
               let payload = Request(
                   messages: messages,
                   system: system,
                   model: options.model.rawValue,
                   max_tokens: options.maxTokens,
                   stop_sequences: options.stopSequences.nilIfEmptyArray,
                   temperature: options.temperature,
                   stream: true
               )
               if options.printToConsole {
                   print("[ChatLLM] System: \(system ?? "none")\n\(messages)")
               }
           } catch {
               continuation.finish(throwing: error)
               return
           }

           let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
           var urlRequest = URLRequest(url: endpoint)
           urlRequest.httpMethod = "POST"
           urlRequest.httpBody = try! JSONEncoder().encode(payload)
           urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
           urlRequest.setValue(credentials.apiKey, forHTTPHeaderField: "X-API-Key")
           urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

           let src = EventSource(urlRequest: urlRequest)
           var message = LLMMessage(role: .assistant, content: options.responsePrefix)

            src.onComplete { statusCode, reconnect, error in
                if let statusCode, statusCode / 100 == 2 {
                    if options.printToConsole {
                        print("[ChatLLM] Response:\n\(message.content)")
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
           src.addEventListener("completion") { id, event, data in
               guard let data, data != "[DONE]" else { return }
               do {
                   let decoded = try JSONDecoder().decode(Response.self, from: Data(data.utf8))
                   message.content += decoded.completion
                   continuation.yield(message)
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
    func convertToAnthropicPrompt() throws -> (system: String?, messages: [ClaudeMessage]) {
        var system: String?
        var messages = [ClaudeMessage]()
        for (i, message) in self.enumerated() {
            // Extract top system message
            if message.role == .system, i == 0 {
                system = message.content
                continue
            }
            messages.append(try message.claudeMessage())
        }
        // TODO: merge contiguous messages with the same roles
        return (system, messages)
    }
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

    }
}

enum ClaudeRole: String, Equatable, Codable {
    case user
    case assistant
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

struct ClaudeMessage: Equatable, Codable {
    var role: ClaudeRole
    var content: [Content]

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
            case image
            case text
        }

        var type: ContentType
        var text: String?
        var source: Source?

        struct Source: Equatable, Codable {
            var type: String
            var media_type: String
            var data: String // base64
        }
    }
}
