import SwiftUI
import ChatToys
import JavaScriptCore

@MainActor
class Tools: ObservableObject {
    init() {}

    let jsCtx = JSContext()!

    var functions: [LLMFunction] {
        [
            LLMFunction(name: "eval", description: "Executes a JS expression and returns the result. Use for math, text manipulation, logic, etc.", parameters: ["expr": .string(description: "JS expression or self-calling function")]),
            LLMFunction(name: "appleScript", description: "Evaluate AppleScript to perform operations on the user's system", parameters: ["script": .string(description: nil)])
        ]
    }

    enum ToolError: Error {
        case unknownTool
        case wrongArgs
        case unavailable
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
        case "appleScript":
            if let params = functionCall.argumentsJson as? [String: String], let script = params["script"] {
                #if os(macOS)
                return try await Scripting.runAppleScript(script: script) ?? "(No result)"
                #else
                throw ToolError.unavailable
                #endif
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

            func received(message: LLMMessage, new: Bool) {
                if !new { messages.removeLast() }
                messages.append(message)
                DispatchQueue.main.async {
                    if new {
                        self.messages.append(message)
                    } else {
                        self.messages[self.messages.count - 1] = message
                    }
                }
            }

            do {
                while true {
                    // TODO: truncate prompt
                    var incoming: LLMMessage?
                    for try await partial in llm.completeStreaming(prompt: messages, functions: self.tools.functions) {
                        received(message: partial, new: incoming == nil)
                        incoming = partial
                    }
                    var functionResponses = [LLMMessage.FunctionResponse]()
                    for fn in incoming?.functionCalls ?? [] {
                        let res = try await self.tools.handle(functionCall: fn)
                        functionResponses.append(.init(id: fn.id, functionName: fn.name, text: res))
                    }
                    if functionResponses.count > 0 {
                        received(message: .init(functionResponses: functionResponses), new: true)
                    } else {
                        break // Model is done responding
                    }
                }
                DispatchQueue.main.async {
                    self.botIsTyping = false
                }
            } catch {
                let text = "Error: \(error)"
                received(message: .init(role: .system, content: text), new: true)
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
                    ForEachUnidentifiable(message.functionCalls) { fn, _ in
                        Text("\(fn.name)(\(fn.arguments))")
                            .font(.system(.body, design: .monospaced))
                            .withStandardMessagePadding
                    }
                }
            case .function:
                ForEachUnidentifiable(message.functionResponses) { item, _ in
                    Text(item.text)
                        .font(.system(.body, design: .monospaced))
                        .withStandardMessagePadding
                        .foregroundColor(.white)
                        .background(.black)
                }
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
