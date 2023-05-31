import SwiftUI
import ChatToys

enum LLM: String, Equatable, Codable, CaseIterable {
    case chatGPT
    case claude

    static func create() -> any ChatLLM {
        let llm: LLM = .init(rawValue: UserDefaults.standard.string(forKey: "llm") ?? "") ?? .chatGPT
        let key = UserDefaults.standard.string(forKey: "key") ?? ""
        switch llm {
        case .chatGPT:
            return ChatGPT(credentials: OpenAICredentials(apiKey: key))
        case .claude:
            return Claude(credentials: AnthropicCredentials(apiKey: key), options: .init(model: .claudeInstantV1))
        }
    }
}

struct SettingsView: View {
    @AppStorage("llm") private var llm = LLM.chatGPT
    @AppStorage("key") private var key = ""

    var body: some View {
        Form {
            Section {
                TextField("API key", text: $key)
                Picker("LLM", selection: $llm) {
                    ForEach(LLM.allCases, id: \.self) {
                        Text($0.rawValue)
                    }
                }.pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}
