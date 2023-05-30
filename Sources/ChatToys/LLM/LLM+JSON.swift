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

    public func completeStreamingWithJSONOutputSingleObject<T: Codable>(prompt: [LLMMessage], example: T) -> AsyncThrowingStream<T, Error> {
        let jsonPrompt = """
Output your answer as a valid JSON object, in this exact format:
\(example.jsonStringNotPretty)
Final output, ONLY the valid JSON in the structure above:
"""
        let fullPrompt: [LLMMessage] = prompt + [.init(role: .system, content: jsonPrompt)]
        return AsyncThrowingStream { cont in
            Task {
                do {
                    for try await partial in self.completeStreaming(prompt: fullPrompt) {
                        for tryCloseArray in [false, true] {
                            var text = partial.content
                            if tryCloseArray {
                                if text.hasSuffix(",") {
                                    _ = text.popLast()
                                }
                                text = text + "]"
                            }
                            if let json = try? JSONDecoder().decode(T.self, from: text.data(using: .utf8)!) {
                                cont.yield(json)
                                break
                            }
                        }
                    }
                    cont.finish()
                }
                catch {
                    cont.yield(with: .failure(error))
                }
            }
        }
    }

    public func completeStreamingWithJSONOutput<T: Codable>(prompt: [LLMMessage], examples: [T]) -> AsyncThrowingStream<T, Error> {
        return AsyncThrowingStream { cont in
            Task {
                var count = 0
                do {
                    for try await partial in self.completeStreamingWithJSONOutputSingleObject(prompt: prompt, example: examples) {
                        for object in partial.suffix(from: count) {
                            cont.yield(object)
                        }
                        count = partial.count
                    }
                    cont.finish()
                }
                catch {
                    cont.yield(with: .failure(error))
                }
            }
        }
//        return completeStreamingWithJSONOutputSingleObject(prompt: prompt, example: examples).map { array in
//            var lastObject =
//        }
//        var jsonPrompt = """
//Output your answer as one or more JSON objects, each on one line.
//Example output:
//"""
//        for example in examples {
//            jsonPrompt += "\n" + example.jsonStringNotPretty
//        }
////        if examples.count == 1 {
////            jsonPrompt += "\n" + examples[0].jsonStringNotPretty
////        }
//        jsonPrompt += "\nFinal output, one complete JSON object per line, in the exact structure above, NO newlines within objects:"
//        let fullPrompt: [LLMMessage] = prompt + [.init(role: .system, content: jsonPrompt)]
//        return completeStreamingLineByLine(prompt: fullPrompt).compactMap { str in
//            let str2 = str.removing(suffix: ",")
//            return try? JSONDecoder().decode(T.self, from: str2.data(using: .utf8)!)
//        }
    }
}
