import SwiftUI
import ChatToys

enum LLM: String, Equatable, Codable, CaseIterable {
    case chatGPT
    case gpt4
    case claude

    static func create() -> any ChatLLM {
        let llm: LLM = .init(rawValue: UserDefaults.standard.string(forKey: "llm") ?? "") ?? .chatGPT
        let key = UserDefaults.standard.string(forKey: "key") ?? ""
        let orgId = UserDefaults.standard.string(forKey: "orgId") ?? ""
        switch llm {
        case .chatGPT:
            return ChatGPT(credentials: OpenAICredentials(apiKey: key, orgId: orgId), options: .init(model: .gpt35_turbo, printToConsole: true))
        case .gpt4:
            return ChatGPT(credentials: OpenAICredentials(apiKey: key, orgId: orgId), options: .init(model: .gpt4, printToConsole: true))
        case .claude:
            return Claude(credentials: AnthropicCredentials(apiKey: key), options: .init(model: .claudeV1, printToConsole: true))
        }
    }
}

struct SettingsView: View {
    @AppStorage("llm") private var llm = LLM.chatGPT
    @AppStorage("key") private var key = ""
    @AppStorage("orgId") private var orgId = ""

    var body: some View {
        Form {
            Section {
                TextField("API key", text: $key)
                TextField("Organization ID (OpenAI, optional)", text: $orgId)
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
