import SwiftUI
import ChatToys

enum LLM: String, Equatable, Codable, CaseIterable {
    case chatGPT
    case gpt4
    case claude
    case llama

    static func create() -> any ChatLLM {
        let llm: LLM = .init(rawValue: UserDefaults.standard.string(forKey: "llm") ?? "") ?? .chatGPT
        let key = UserDefaults.standard.string(forKey: "key") ?? ""
        let orgId = UserDefaults.standard.string(forKey: "orgId") ?? ""
        let llamaModel = UserDefaults.standard.string(forKey: "llamaModel") ?? ""
        switch llm {
        case .chatGPT:
            return ChatGPT(credentials: OpenAICredentials(apiKey: key, orgId: orgId), options: .init(model: .gpt35_turbo, printToConsole: true, printCost: false))
        case .gpt4:
            return ChatGPT(credentials: OpenAICredentials(apiKey: key, orgId: orgId), options: .init(model: .gpt4, printToConsole: true))
        case .claude:
            return Claude(credentials: AnthropicCredentials(apiKey: key), options: .init(model: .claudeInstant1, printToConsole: true))
        case .llama:
            return LlamaCPP(modelName: llamaModel, tokenLimit: 512)
        }
    }
}

struct SettingsView: View {
    @AppStorage("llm") private var llm = LLM.chatGPT
    @AppStorage("key") private var key = ""
    @AppStorage("orgId") private var orgId = ""
    @AppStorage("llamaModel") private var llamaModel = ""

    var body: some View {
        Form {
            Section {
                TextField("API key", text: $key)
                TextField("Organization ID (OpenAI, optional)", text: $orgId)
                TextField("Llama Model", text: $llamaModel)
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
