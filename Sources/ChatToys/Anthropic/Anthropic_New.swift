import Foundation

public struct ClaudeNewAPI {
    public enum Model: String, Equatable {
        case claudeInstant12 = "claude-instant-1.2"
        case claude2 = "claude-2"
        case claude3Sonnet = "claude-3-sonnet-20240229" // medium
        case claude3Opus = "claude-3-opus-20240229" // large
    }

    public struct Options {
        public var model: Model
        public var maxTokens: Int
        public var stopSequences: [String]
        public var temperature: Double
        public var printToConsole: Bool
        public var responsePrefix: String // Forces the model to use this as the beginning of the response. (This prefix _will_ be included in the output).

        public init(model: Model = .claudeInstant12, maxTokens: Int = 1000, stopSequences: [String] = [], temperature: Double = 0.5, printToConsole: Bool = false, responsePrefix: String = "") {
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

extension ClaudeNewAPI: ChatLLM {
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
        var content: [ClaudeMessage.Content]
    }

    public var tokenLimit: Int {
        switch options.model {
        case .claudeInstant12, .claude2: return 100_000
        case .claude3Sonnet, .claude3Opus: return 200_000
        }
    }


    public func completeStreaming(prompt: [LLMMessage]) -> AsyncThrowingStream<LLMMessage, Error> {
       return AsyncThrowingStream { continuation in
           var payload: Request
           do {
               let (system, messages) = try prompt.convertToAnthropicPrompt()
               payload = Request(
                   messages: messages,
                   system: system,
                   model: options.model.rawValue,
                   max_tokens: options.maxTokens,
                   stop_sequences: options.stopSequences.nilIfEmptyArray,
                   temperature: options.temperature,
                   stream: false// true
               )
               if let prefix = options.responsePrefix.nilIfEmpty {
                   payload.messages.append(.init(role: .assistant, content: [.init(type: .text, text: prefix)]))
               }
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

           Task { [urlRequest] in
               do {
                   let (data, response) = try await URLSession.shared.data(for: urlRequest)
                   if (response as? HTTPURLResponse)?.statusCode != 200 {
                       print("[Anthropic] Failed with error: \(String(data: data, encoding: .utf8)!)")
                   }
                   let resp = try JSONDecoder().decode(Response.self, from: data)
                   let text = resp.content.first?.text ?? ""
                   continuation.yield(LLMMessage(role: .assistant, content: options.responsePrefix + text))
                   continuation.finish()
               } catch {
                   continuation.finish(throwing: error)
               }
           }


//           let src = EventSource(urlRequest: urlRequest)
//           var message = LLMMessage(role: .assistant, content: options.responsePrefix)
//
//            src.onComplete { statusCode, reconnect, error in
//                if let statusCode, statusCode / 100 == 2 {
//                    if options.printToConsole {
//                        print("[ChatLLM] Response:\n\(message.content)")
//                    }
//                    continuation.finish()
//                } else {
//                    if let error {
//                        continuation.yield(with: .failure(error))
//                    } else if let statusCode {
//                        continuation.yield(with: .failure(LLMError.http(statusCode)))
//                    } else {
//                        continuation.yield(with: .failure(LLMError.unknown(nil)))
//                    }
//                }
//            }
//           src.addEventListener("completion") { id, event, data in
//               guard let data, data != "[DONE]" else { return }
//               do {
//                   let decoded = try JSONDecoder().decode(Response.self, from: Data(data.utf8))
//                   message.content += decoded.completion
//                   continuation.yield(message)
//               } catch {
//                   print("Chat completion error: \(error)")
//                   continuation.yield(with: .failure(error))
//               }
//           }
//            src.connect()
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
