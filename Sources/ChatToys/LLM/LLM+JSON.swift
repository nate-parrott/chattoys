import Foundation

enum JSONLLMError: Error {
    case failedToExtractJSON
}

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

    public func completeStreamingWithJSONObject<T: Codable>(prompt: [LLMMessage], type: T.Type, completeLinesOnly: Bool = false) -> AsyncThrowingStream<T, Error> {
        return AsyncThrowingStream { cont in
            Task {
                do {
                    var lastText = ""
                    for try await partial in self.completeStreaming(prompt: prompt) {
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
}

// MARK: - Non-streaming convenience functions
extension ChatLLM {
    public func completeJSONObject<T: Codable>(prompt: [LLMMessage], type: T.Type) async throws -> T {
        var last: T? = nil
        for try await json in completeStreamingWithJSONObject(prompt: prompt, type: type) {
            last = json
        }
        guard let final = last else {
            throw JSONLLMError.failedToExtractJSON
        }
        return final
    }
}

// MARK: - Convenience

extension ChatLLM {
    /// Attempts to extract partial JSON output and periodically deliver it
    /// Example will be added to the prompt
    public func completeStreamingWithJSONObject<T: Codable>(prompt: [LLMMessage], example: T) -> AsyncThrowingStream<T, Error> {
        let jsonPrompt = """
Output your answer as a valid JSON object, in this exact format:
\(example.jsonStringNotPretty)
Final output, ONLY the valid JSON in the structure above:
"""
        let fullPrompt: [LLMMessage] = prompt + [.init(role: .system, content: jsonPrompt)]
        return completeStreamingWithJSONObject(prompt: fullPrompt, type: T.self)
    }

    // Task is something like "You are renaming tabs to be concise."
    // Guidelines are things like "2-3 words", "English", "You are an expert translator"
    public func streamJSON<Input: Codable, Output: Codable>(task: String, guidelines: [String], input: Input, examples: [(Input, Output)], completeLinesOnly: Bool = false) -> AsyncThrowingStream<Output, Error> {
        var prompt = [LLMMessage]()

        var p1Lines = [
            "Task: \(task)",
            "You will receive input as JSON, and must output a JSON code block of a particular schema."
        ]
        if guidelines.count > 0 {
            p1Lines.append("Guidelines:")
            p1Lines += guidelines.map { " - \($0)" }
        }
//        if examples.count > 0 {
//            p1Lines.append(examples.count == 1 ? "Example:" : "Examples:")
//        }
        prompt.append(.init(role: .system, content: p1Lines.joined(separator: "\n")))

        for example in examples {
            prompt.append(.init(role: .user, content: "```\n\(example.0.jsonString)\n```"))
            prompt.append(.init(role: .assistant, content: "```\n\(example.1.jsonString)\n```"))
        }
        prompt.append(.init(role: .user, content: "```\n\(input.jsonString)\n```"))
        return completeStreamingWithJSONObject(prompt: prompt, type: Output.self, completeLinesOnly: completeLinesOnly)
    }

    // Task is something like "You are renaming tabs to be concise."
    // Guidelines are things like "2-3 words", "English", "You are an expert translator"
    public func json<Input: Codable, Output: Codable>(task: String, guidelines: [String], input: Input, examples: [(Input, Output)]) async throws -> Output {
        var last: Output?
        for try await x in streamJSON(task: task, guidelines: guidelines, input: input, examples: examples, completeLinesOnly: true) {
            last = x
        }
        guard let final = last else {
            throw JSONLLMError.failedToExtractJSON
        }
        return final
    }
}
