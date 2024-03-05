import SwiftUI
import ChatToys

enum LLM: String, Equatable, Codable, CaseIterable {
    case chatGPT
    case chatGPT16k
    case gpt4
    case gpt4Vision
    case claude
    case llama
    case perplexityOnline7b

    static func createFunctionCalling() -> (any FunctionCallingLLM)? {
        let llm: LLM = .init(rawValue: UserDefaults.standard.string(forKey: "llm") ?? "") ?? .chatGPT
        let key = UserDefaults.standard.string(forKey: "key") ?? ""
        let orgId = UserDefaults.standard.string(forKey: "orgId") ?? ""
        let llamaModel = UserDefaults.standard.string(forKey: "llamaModel") ?? ""
        switch llm {
        case .chatGPT, .chatGPT16k:
            let model = (llm == .chatGPT16k) ? ChatGPT.Model.gpt35_turbo_16k : ChatGPT.Model.gpt35_turbo
            return ChatGPT(credentials: OpenAICredentials(apiKey: key, orgId: orgId), options: .init(model: model, printToConsole: true, printCost: false))
        case .gpt4:
            return ChatGPT(credentials: OpenAICredentials(apiKey: key, orgId: orgId), options: .init(model: .gpt4, printToConsole: true))
        case .gpt4Vision:
            return ChatGPT(credentials: OpenAICredentials(apiKey: key, orgId: orgId), options: .init(model: .gpt4_vision_preview, maxTokens: 4096))
        case .claude, .llama, .perplexityOnline7b:
            return nil
        }
    }

    static func create() -> any ChatLLM {
        let llm: LLM = .init(rawValue: UserDefaults.standard.string(forKey: "llm") ?? "") ?? .chatGPT
        let key = UserDefaults.standard.string(forKey: "key") ?? ""
        let orgId = UserDefaults.standard.string(forKey: "orgId") ?? ""
        let llamaModel = UserDefaults.standard.string(forKey: "llamaModel") ?? ""
        switch llm {
        case .chatGPT, .chatGPT16k:
            let model = (llm == .chatGPT16k) ? ChatGPT.Model.gpt35_turbo_16k : ChatGPT.Model.gpt35_turbo
            return ChatGPT(credentials: OpenAICredentials(apiKey: key, orgId: orgId), options: .init(model: model, printToConsole: true, printCost: false))
        case .gpt4:
            return ChatGPT(credentials: OpenAICredentials(apiKey: key, orgId: orgId), options: .init(model: .gpt4, printToConsole: true))
        case .claude:
            return ClaudeNewAPI(credentials: AnthropicCredentials(apiKey: key), options: .init(model: .claude3Sonnet, printToConsole: true))
        case .llama:
            return LlamaCPP(modelName: llamaModel, tokenLimit: 512)
        case .gpt4Vision:
            return ChatGPT(credentials: OpenAICredentials(apiKey: key, orgId: orgId), options: .init(model: .gpt4_vision_preview, maxTokens: 4096, printCost: false))
        case .perplexityOnline7b:
            return PerplexityLLM(credentials: .init(apiKey: key), options: .init(model: .pplx7bOnline))
        }
    }
}

extension OpenAIEmbedder {
    static func create() -> OpenAIEmbedder {
        let key = UserDefaults.standard.string(forKey: "key") ?? ""
        let orgId = UserDefaults.standard.string(forKey: "orgId") ?? ""
        return .init(credentials: .init(apiKey: key, orgId: orgId))
    }
}

struct SettingsView: View {
    @AppStorage("llm") private var llm = LLM.chatGPT
    @AppStorage("key") private var key = ""
    @AppStorage("orgId") private var orgId = ""
    @AppStorage("llamaModel") private var llamaModel = ""
    @AppStorage("bingKey") private var bingKey = ""

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
                TextField("Bing key", text: $bingKey)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}
