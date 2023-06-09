import Foundation

extension ChatLLM {
    public func completeStreamingLineByLine(prompt: [LLMMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { cont in
            Task {
                var completeLineCount = 0
                var lastLine: String?
                do {
                    for try await partial in self.completeStreaming(prompt: prompt) {
                        var lines = partial.content.components(separatedBy: .newlines)
                        lastLine = lines.popLast()
                        let completeLines = lines
                        for newCompleteLine in completeLines.suffix(from: completeLineCount) {
                            cont.yield(with: .success(newCompleteLine))
                        }
                        completeLineCount = completeLines.count
                    }
                    if let lastLine = lastLine?.nilIfEmptyOrJustWhitespace {
                        cont.yield(with: .success(lastLine))
                    }
                    cont.finish()
                }
                catch {
                    cont.yield(with: .failure(error))
                }
            }
        }
    }

    public func completeStreamingWithJSONObject<T: Codable>(promptWithJSONExplanation: [LLMMessage], type: T.Type, completeLinesOnly: Bool = false) -> AsyncThrowingStream<T, Error> {
        return AsyncThrowingStream { cont in
            Task {
                do {
                    var lastText = ""
                    for try await partial in self.completeStreaming(prompt: promptWithJSONExplanation) {
                        lastText = partial.content.byExtractingOnlyCodeBlocks.removing(prefix: "json")

                        var textToParse = lastText
                        if completeLinesOnly {
                            textToParse = textToParse.dropLastLine
                        }
                        if let json = try? JSONDecoder().decode(T.self, from: textToParse.capJson.data(using: .utf8)!) {
                            cont.yield(json)
//                            break
                        }
                    }
                    let json = try JSONDecoder().decode(T.self, from: lastText.capJson.data(using: .utf8)!)
                    cont.yield(json)
                    cont.finish()
                }
                catch {
                    cont.yield(with: .failure(error))
                }
            }
        }
    }

    /// Attempts to extract partial JSON output and periodically deliver it
    public func completeStreamingWithJSONObject<T: Codable>(prompt: [LLMMessage], example: T) -> AsyncThrowingStream<T, Error> {
        let jsonPrompt = """
Output your answer as a valid JSON object, in this exact format:
\(example.jsonStringNotPretty)
Final output, ONLY the valid JSON in the structure above:
"""
        let fullPrompt: [LLMMessage] = prompt + [.init(role: .system, content: jsonPrompt)]
        return completeStreamingWithJSONObject(promptWithJSONExplanation: fullPrompt, type: T.self)
    }

    public func completeJSONObject<T: Codable>(promptWithJSONExplanation: [LLMMessage], type: T.Type) async throws -> T? {
        var last: T? = nil
        for try await json in completeStreamingWithJSONObject(promptWithJSONExplanation: promptWithJSONExplanation, type: type) {
            last = json
        }
        return last
    }
}
