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

        Task {
            do {
                var hasAppended = false
                for try await partial in LLM.create().completeStreaming(prompt: self.messages) {
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
            }
        }
    }
}
