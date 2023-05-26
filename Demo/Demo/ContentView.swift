import SwiftUI
import ChatToys

struct ContentView: View {
    @State private var prompt = ""
    @State private var completion: String = ""
    @AppStorage("key") private var key = ""
    @State private var error: Error?

    var body: some View {
        Form {
            Section {
                TextField("API key", text: $key)
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
            let openAI = OpenAICredentials(apiKey: key)
            let chatLLM = ChatGPT(credentials: openAI)
            self.completion = ""
            self.error = nil
            do {
                for try await partial in chatLLM.completeStreaming(prompt: messages) {
                    completion = partial.content
                }
            } catch {
                self.error = error
            }
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
