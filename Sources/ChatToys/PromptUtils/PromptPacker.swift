import Foundation

public struct Prompt: Equatable {
    var charsPerToken: Double = 3
    var joiner: String = "\n"
    var roleTokenCount: Int = 2

    public init() {
    }

    // By default, priority increases with index
    public mutating func append(_ text: String, role: LLMMessage.Role, priority: Double? = nil, canTruncateToLength: Int? = nil, canOmit: Bool = false, omissionMessage: String? = nil, trim: Bool = true, functionCall: LLMMessage.FunctionCall? = nil, nameOfFunctionThatProduced: String? = nil) {
        let priority = priority ?? Double(parts.count)
        let textFinal = trim ? text.trimmed.dropCommentedLines : text
        parts.append(Part(
            id: UUID().uuidString,
            text: textFinal,
            role: role,
            inResponseToFunctionName: nameOfFunctionThatProduced,
            functionCall: functionCall,
            priority: priority,
            canTruncateToLength: canTruncateToLength,
            canOmit: canOmit, 
            omissionMessage: omissionMessage
        )
        )
    }

    mutating func reduce(toTokenBudget budget: Int) -> Bool {
        while tokenEstimate > budget {
            // Fudge it a bit since these are all estimates
            if !reduceOnce(tokensToReduceBy: tokenEstimate - budget + 2) {
                return false
            }
        }
        return true
    }

    public var prompt: String {
        parts.map { $0.text }.joined(separator: joiner)   
    }

    public func packedPrompt(tokenCount: Int) -> [LLMMessage] {
        var p = self
        _ = p.reduce(toTokenBudget: tokenCount)
        return p.messages
    }

    public var messages: [LLMMessage] {
        parts.map { part in
                .init(role: part.role, content: part.text, functionCall: part.functionCall, nameOfFunctionThatProduced: part.inResponseToFunctionName)
        }
    }

    public var messageCount: Int {
        parts.count
    }

    // MARK: - Internals

    private struct Part: Equatable {
        var id: String
        var text: String
        var role: LLMMessage.Role
        
        // for role=function
        // TODO: Count tokens for this
        var inResponseToFunctionName: String?

        // for role=assistant
        // TODO: Count tokens for this
        var functionCall: LLMMessage.FunctionCall?

        var priority: Double
        var canTruncateToLength: Int?
        var canOmit: Bool
        var omissionMessage: String? // prompt parts with different omission messages are coalesced
        var canDedupe: Bool = false // if two subsequent parts have the text and `canDedupe` is true, duplicates are dropped
    }

    private var parts: [Part] = []
    var tokenEstimate: Int {
        var chars = 0
        for part in parts {
            chars += part.text.count + roleTokenCount
        }
        chars += max(0, parts.count - 1) * joiner.count
        return charsToTokens(chars)
    }

    private mutating func reduceOnce(tokensToReduceBy: Int) -> Bool {
        // First, try truncating the lowest-priority item with a truncation length
        let lowestPriorityTruncatable = parts
        .filter { $0.canTruncateToLength != nil && $0.canTruncateToLength! < $0.text.count }
        .min { $0.priority < $1.priority }

        if var part = lowestPriorityTruncatable {
            let curTokenLength = charsToTokens(part.text.count)
            // Don't reduce to <4, because we need room for ellipses...
            let newTokenLength = max(4, max(curTokenLength - tokensToReduceBy, charsToTokens(part.canTruncateToLength!)))
            let newCharLength = tokensToChars(newTokenLength)
            part.text = part.text.truncateTail(maxLen: newCharLength)
            part.canTruncateToLength = nil
            updatePart(part)
            return true
        }

        // Then, try omitting the lowest-priority item
        let lowestPriorityOmittable = parts
        .filter { $0.canOmit }
        .min { $0.priority < $1.priority }

        if var part = lowestPriorityOmittable {
            if let omissionMessage = part.omissionMessage {
                part.text = omissionMessage
                part.canOmit = false
                part.canTruncateToLength = nil
                part.canDedupe = true
                updatePart(part)
                dedupe()
                return true
            } else {
                deletePart(part)
                return true
            }
        }

        return false
    }

    private mutating func updatePart(_ part: Part) {
        if let idx = parts.firstIndex(where: { $0.id == part.id }) {
            parts[idx] = part
        }
    }

    private mutating func deletePart(_ part: Part) {
        if let idx = parts.firstIndex(where: { $0.id == part.id }) {
            parts.remove(at: idx)
        }
    }

    private mutating func dedupe() {
        var newParts: [Part] = []
        for part in parts {
            if part.canDedupe, let last = newParts.last, last.text == part.text, last.role == part.role, last.canDedupe {
                continue // drop
            } else {
                newParts.append(part) // keep
            }
        }
        parts = newParts
    }

    // MARK: - Helpers
    private func charsToTokens(_ chars: Int) -> Int {
        Int(ceil(Double(chars) / charsPerToken))
    }

    private func tokensToChars(_ tokens: Int) -> Int {
        Int(floor(Double(tokens) * charsPerToken))
    }
}

extension Prompt: CustomDebugStringConvertible {
    public var debugDescription: String {
        messages.asConversationString
    }
}

extension String {
    var dropCommentedLines: String {
        let parts = components(separatedBy: .newlines)
        return parts.filter { line in
            return !line.trimmed.hasPrefix("%%")
        }.joined(separator: "\n")
    }

    public func truncate(toTokens tokens: Int, charsPerToken: Double = 3) -> String {
        let charLimit =  Int(floor(Double(tokens) * charsPerToken))
        return truncateTail(maxLen: charLimit)
    }
}

