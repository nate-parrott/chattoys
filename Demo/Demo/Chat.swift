import SwiftUI
import ChatToys

struct ChatDemo: View {
    @State private var messages: [LLMMessage] = []
    @State private var text = ""
    @State private var botIsTyping = false

    var body: some View {
        VStack(spacing: 0) {
            ChatThreadView(
                messages: messages, 
                id: {_, index in index }, 
                messageView: { message in
                    TextMessageBubble(Text(message.content), isFromUser: message.role == .user)
                },
                typingIndicator: botIsTyping
            )
            Divider()
            ChatInputView(
                placeholder: "Message", 
                text: $text, 
                sendAction: sendMessage
            )
        }
    }

    private func sendMessage() {
        let text = self.text
        self.text = ""
        messages.append(LLMMessage(role: .user, content: text))
        botIsTyping = true

        // Fit prompt into context window:
        var prompt = Prompt()
        for message in messages {
            prompt.append(message.content, role: message.role, canOmit: true, omissionMessage: "[Older messages hidden]")
        }
        let llm = LLM.create()
        let truncatedPrompt = prompt.packedPrompt(tokenCount: llm.tokenLimitWithWiggleRoom)

        Task {
            do {
                var hasAppended = false
                for try await partial in llm.completeStreaming(prompt: truncatedPrompt) {
                    if hasAppended {
                        messages.removeLast()
                    }
                    messages.append(partial)
                    hasAppended = true
                    self.botIsTyping = false
                }
            } catch {
                let text = "Error: \(error)"
                messages.append(.init(role: .system, content: text))
                self.botIsTyping = false
            }
        }
    }
}
