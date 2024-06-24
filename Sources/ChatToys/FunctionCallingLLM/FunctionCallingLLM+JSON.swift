import Foundation

extension FunctionCallingLLM {
    public func completeStreamingWithJSONObject<T: Codable>(prompt: [LLMMessage], type: T.Type, functions: [LLMFunction], completeLinesOnly: Bool = false) -> AsyncThrowingStream<(LLMMessage, T?), Error> {
        return AsyncThrowingStream { cont in
            Task {
                do {
                    var lastMsg: LLMMessage = .init(assistantMessageWithContent: "")
                    var lastText = ""
                    for try await partial in self.completeStreaming(prompt: prompt, functions: functions) {
                        lastMsg = partial
                        lastText = partial.content.byExtractingOnlyCodeBlocks.removing(prefix: "json")

                        var textToParse = lastText
                        if completeLinesOnly {
                            textToParse = textToParse.dropLastLine
                        }
                        if let json = try? JSONDecoder().decode(T.self, from: textToParse.capJson.data(using: .utf8)!) {
                            cont.yield((partial, json))
//                            break
                        } else {
                            cont.yield((partial, nil))
                        }
                    }
//                    print(lastText)
                    let json = try? JSONDecoder().decode(T.self, from: lastText.capJson.data(using: .utf8)!)
                    cont.yield((lastMsg, json))
                    cont.finish()
                }
                catch {
                    cont.yield(with: .failure(error))
                }
            }
        }
    }
}
