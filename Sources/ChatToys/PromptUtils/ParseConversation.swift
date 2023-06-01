import Foundation

extension LLMMessage {
    /**
        Parses a string like this:

        System: You are an intelligent agent that answers questions.
        Answer all questions truthfully.

        User: hi!
        Assistant: hey!
        U: what's up?
        A: not much, you?
     */
    public static func parseConversation(fromString string: String) -> [LLMMessage] {
        // Parse each line. If it starts with "System:", "User:" or "Assistant:" (or A:, U: or S:), then it's a message.
        // Otherwise, append to previous line.
        // At the end, trim output and remove empty lines.

        func roleFromString(_ string: String) -> LLMMessage.Role? {
            switch string.lowercased() {
            case "system", "s":
                return .system
            case "user", "u", "human", "h":
                return .user
            case "assistant", "a":
                return .assistant
            default:
                return nil
            }
        }

        var messages: [LLMMessage] = []
        var currentMessage: LLMMessage?

        for line in string.components(separatedBy: "\n").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) {
            // Split line on ": " once
            let components = line.split(separator: ":", maxSplits: 1).map { String($0) }
            if components.count == 2, let role = roleFromString(components[0]) {
                // This is a new message
                if let currentMessage = currentMessage {
                    messages.append(currentMessage)
                }
                currentMessage = LLMMessage(role: role, content: components[1])
            } else if line.hasSuffix(":"), let role = roleFromString(components[0]) {
                // This is a new message
                // This is a new message
                if let currentMessage = currentMessage {
                    messages.append(currentMessage)
                }
                currentMessage = LLMMessage(role: role, content: "")
            } else {
                // This is a continuation of the previous message
                if currentMessage != nil {
                    currentMessage!.content += "\n\(line)"
                } else {
                    // if there is no role and no current message, assume "system"
                    currentMessage = LLMMessage(role: .system, content: line)
                }
            }
        }

        if let currentMessage = currentMessage {
            messages.append(currentMessage)
        }

        return messages.map({ $0.byTrimmingWhitespace })
    }

    private var byTrimmingWhitespace: LLMMessage {
        .init(role: role, content: content.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

public extension Sequence where Element == LLMMessage {
    var asConversationString: String {
        let lines = map { msg in
            "\(msg.role.rawValue): \(msg.content)"
        }
        return lines.joined(separator: "\n\n")
    }
}
