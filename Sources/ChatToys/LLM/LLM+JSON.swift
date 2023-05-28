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

    public func completeStreamingWithJSONOutput<T: Codable>(prompt: [LLMMessage], examples: [T]) -> some AsyncSequence {
        var jsonPrompt = """
Output your answer as ONLY valid JSON, with EXACTLY one item per line.
For example:
"""
        for example in examples {
            jsonPrompt += "\n" + example.jsonStringNotPretty
        }
        let fullPrompt: [LLMMessage] = prompt + [.init(role: .system, content: jsonPrompt)]
        return completeStreamingLineByLine(prompt: fullPrompt).compactMap { str in
            try? JSONDecoder().decode(T.self, from: str.data(using: .utf8)!)
        }
    }
}

