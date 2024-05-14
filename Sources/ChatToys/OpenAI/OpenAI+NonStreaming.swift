import Foundation

extension ChatGPT {
    struct NonStreamingResponse: Codable {
        struct Choice: Codable {
            var message: ChatGPT.Message
            var logprobs: LogProbs?

            struct LogProbs: Codable {
                var content: [TokenWithProb]?
                struct TokenWithProb: Codable {
                    var token: String
                    var logprob: Double
                }
            }

            var logProb: Double? {
                let probs = (logprobs?.content ?? []).compactMap { $0.logprob }
                if probs.count == 0 { return nil }
                return probs.reduce(0, { $0 + $1 })
            }
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
        let (data, resp) = try await URLSession.shared.data(for: request)
//        print("resp: \(String(data: data, encoding: .utf8)!)")

        if let code = (resp as? HTTPURLResponse)?.statusCode, code / 100 != 2 {
            throw LLMError.unknown(String(data: data, encoding: .utf8))
        }

        let response = try JSONDecoder().decode(NonStreamingResponse.self, from: data)

        guard let result = response.choices.first?.message else {
            throw LLMError.unknown(String(data: data, encoding: .utf8))
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
        case .gpt4: return (3, 6)
        case .gpt4_32k: return (6, 12)
        case .gpt35_turbo_0125: return (0.05, 0.15)
        case .gpt4_turbo_preview: return (1, 3)
        case .gpt4_vision_preview, .gpt4_turbo, .gpt4_o: return (0, 0) // TODO
        case .custom: return (0, 0)
        }
    }
}
