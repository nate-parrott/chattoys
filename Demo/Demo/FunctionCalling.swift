import SwiftUI
import ChatToys
import JavaScriptCore

@MainActor
class Tools: ObservableObject {
    init() {}

    let jsCtx = JSContext()!

    var functions: [LLMFunction] {
        [
            LLMFunction(name: "eval", description: "Executes a JS expression and returns the result. Use for math, text manipulation, logic, etc.", parameters: ["expr": .string(description: "JS expression or self-calling function")])
        ]
    }

    enum ToolError: Error {
        case unknownTool
        case wrongArgs
    }

    func handle(functionCall: LLMMessage.FunctionCall) async throws -> String {
        switch functionCall.name {
        case "eval":
            if let params = functionCall.argumentsJson as? [String: String], let expr = params["expr"] {
                let res = jsCtx.evaluateScript(expr)!
                return res.toString()
            } else {
                throw ToolError.wrongArgs
            }
        default: throw ToolError.unknownTool
        }
    }
}

struct FunctionCallingDemo: View {
    @State private var messages: [LLMMessage] = []
    @State private var text = ""
    @State private var botIsTyping = false
    @StateObject private var tools = Tools()

    var body: some View {
        VStack(spacing: 0) {
            ChatThreadView(
                messages: messages,
                id: {_, index in index },
                messageView: { message in
                    ToolChatMessage(message: message)
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

        // TODO: Prompt packer should take function calls into account
        guard let llm = LLM.createFunctionCalling() else {
            messages.append(.init(role: .system, content: "The selected LLM doesn't support function-calling"))
            return
        }

        Task {
            var messages = self.messages

            func append(message: LLMMessage) {
                messages.append(message)
                DispatchQueue.main.async {
                    self.messages.append(message)
                }
            }

            do {
                while true {
                    // TODO: truncate prompt
                    let resp = try await llm.complete(prompt: messages, functions: self.tools.functions)
                    append(message: resp)
                    if let fn = resp.functionCall {
                        let res = try await self.tools.handle(functionCall: fn)
                        append(message: .init(role: .function, content: res, nameOfFunctionThatProduced: fn.name))
                    } else {
                        break
                    }
                }
                DispatchQueue.main.async {
                    self.botIsTyping = false
                }
            } catch {
                let text = "Error: \(error)"
                append(message: .init(role: .system, content: text))
                DispatchQueue.main.async {
                    self.botIsTyping = false
                }
            }
        }
    }
}

private struct ToolChatMessage: View {
    var message: LLMMessage

    var body: some View {
        MessageBubble(isFromUser: message.role == .user) {
            switch message.role {
            case .system, .user:
                Text(message.content)
                    .withStandardMessagePadding
            case .assistant:
                VStack(alignment: .leading) {
                    if message.content != "" {
                        Text(message.content).withStandardMessagePadding
                    }
                    if let fn = message.functionCall {
                        Text("\(fn.name)(\(fn.arguments))")
                            .font(.system(.body, design: .monospaced))
                            .withStandardMessagePadding
                    }
                }
            case .function:
                Text(message.content)
                    .font(.system(.body, design: .monospaced))
                    .withStandardMessagePadding
                    .foregroundColor(.white)
                    .background(.black)
            }
        }
    }
}

extension View {
    var withStandardMessagePadding: some View {
        self
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
    }
}
