import SwiftUI
import ChatToys

struct ContentView: View {
    @State private var prompt = ""
    @State private var completion: String = ""
    @AppStorage("llm") private var llm = LLM.chatGPT
    @AppStorage("key") private var key = ""
    @State private var error: Error?

    enum LLM: String, Equatable, Codable, CaseIterable {
        case chatGPT
        case claude
    }

    var body: some View {
        Form {
            Section {
                TextField("API key", text: $key)
                Picker("LLM", selection: $llm) {
                    ForEach(LLM.allCases, id: \.self) {
                        Text($0.rawValue)
                    }
                }.pickerStyle(.segmented)
                TextField("Prompt", text: $prompt, onCommit: complete)
                Button("Complete Chat", action: complete)
            }
            if let error {
                Section {
                    Text("Error: \("\(error)"))")
                        .foregroundColor(.red)
                }
            }
            if completion != "" {
                Section {
                    Text(completion)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func complete() {
        Task {
            let messages = [LLMMessage(role: .user, content: prompt)]
            self.completion = ""
            self.error = nil
            do {
                for try await partial in createLLM.completeStreaming(prompt: messages) {
                    completion = partial.content
                }
            } catch {
                self.error = error
            }
        }
    }

    private var createLLM: any ChatLLM {
        switch llm {
        case .chatGPT:
            return ChatGPT(credentials: OpenAICredentials(apiKey: key))
        case .claude:
            return Claude(credentials: AnthropicCredentials(apiKey: key), options: .init(model: .claudeInstantV1))
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
