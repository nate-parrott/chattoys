import Foundation
//
//public struct Ollama: ChatLLM {
//    // curl -X POST http://localhost:11434/api/generate -d '{"model": "llama2", "prompt":"Why is the sky blue?"}'
//    var baseURL: URL
//    var model: String
//
//    public init(baseURL: URL = URL(string: "http://localhost:11434/")!, model: String = "llama2") {
//        self.baseURL = baseURL
//        self.model = model
//    }
//
//    var tokenLimit: Int { 4096 }
//
//    func completeStreaming(prompt: [LLMMessage]) -> AsyncThrowingStream<LLMMessage, Error> {
//        func completeStreaming(prompt: [LLMMessage]) -> AsyncThrowingStream<LLMMessage, Error> {
//            let request = createChatRequest(prompt: prompt, stream: true)
//
//            if options.printToConsole {
//                print("OpenAI request:\n\((prompt.asConversationString))")
//            }
//
//            return AsyncThrowingStream { continuation in
//                let src = EventSource(urlRequest: request)
//
//                var message = Message(role: .assistant, content: "")
//
//                src.onComplete { statusCode, reconnect, error in
//                    if let statusCode, statusCode / 100 == 2 {
//                        if options.printToConsole {
//                            print("OpenAI response:\n\((message.content))")
//                        }
//                        continuation.finish()
//                    } else {
//                        if let error {
//                            continuation.yield(with: .failure(error))
//                        } else if let statusCode {
//                            continuation.yield(with: .failure(LLMError.http(statusCode)))
//                        } else {
//                            continuation.yield(with: .failure(LLMError.unknown))
//                        }
//                    }
//                }
//                src.onMessage { id, event, data in
//                    guard let data, data != "[DONE]" else { return }
//                    do {
//                        let decoded = try JSONDecoder().decode(ChatCompletionStreamingResponse.self, from: Data(data.utf8))
//                        if let delta = decoded.choices.first?.delta {
//                            message.role = delta.role ?? message.role
//                            message.content += delta.content ?? ""
//                            continuation.yield(message.asLLMMessage)
//                        }
//                    } catch {
//                        print("Chat completion error: \(error)")
//                        continuation.yield(with: .failure(error))
//                    }
//                }
//                src.connect()
//            }
//        }
//
//        private func createChatRequest(prompt: [LLMMessage]) -> URLRequest {
//            let url = baseURL.appendingPathComponent("api/generate")
//            var request = URLRequest(url: url)
//            request.httpMethod = "POST"
//            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//            let body: [String: Any] = [
//                "model": "llama2",
//                "prompt": prompt.asConversationString
//            ]
//            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
//            return request
//        }
//    }    
//}
