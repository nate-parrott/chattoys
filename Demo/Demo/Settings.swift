import SwiftUI
import ChatToys

enum LLM: String, Equatable, Codable, CaseIterable {
    case chatGPT
    case chatGPT16k
    case gpt4o
    case gpt4Vision
    case claude
    case ollama
    case perplexityOnline7b
    case groq
    case openrouterReasoning

    static func createFunctionCalling() -> (any FunctionCallingLLM)? {
        let llm: LLM = .init(rawValue: UserDefaults.standard.string(forKey: "llm") ?? "") ?? .chatGPT
        let key = UserDefaults.standard.string(forKey: "key") ?? ""
        let orgId = UserDefaults.standard.string(forKey: "orgId") ?? ""

        switch llm {
        case .chatGPT, .chatGPT16k:
            let model = (llm == .chatGPT16k) ? ChatGPT.Model.gpt35_turbo_16k : ChatGPT.Model.gpt35_turbo
            return ChatGPT(credentials: OpenAICredentials(apiKey: key, orgId: orgId), options: .init(model: model, printToConsole: true, printCost: false))
        case .gpt4o:
            return ChatGPT(credentials: OpenAICredentials(apiKey: key, orgId: orgId), options: .init(model: .gpt4_omni, printToConsole: true))
        case .gpt4Vision:
            return ChatGPT(credentials: OpenAICredentials(apiKey: key, orgId: orgId), options: .init(model: .gpt4_vision_preview, maxTokens: 4096))
        case .claude:
            return Claude(credentials: AnthropicCredentials(apiKey: key), options: .init(model: .claude3Haiku, printToConsole: true, responsePrefix: ""))
        case .openrouterReasoning:
            return ChatGPT(credentials: OpenAICredentials(apiKey: key, orgId: orgId), options: .init(model: .custom2(ChatGPT.Model.CustomModel(name: "anthropic/claude-3.7-sonnet:thinking", tokenLimit: 128_000, openrouter_reasoning: true)), baseURL: .openRouterOpenAIChatEndpoint))
        case .ollama, .perplexityOnline7b, .groq:
            return nil
        }
    }

    static func create() -> any ChatLLM {
        let llm: LLM = .init(rawValue: UserDefaults.standard.string(forKey: "llm") ?? "") ?? .chatGPT
        let key = UserDefaults.standard.string(forKey: "key") ?? ""
        let orgId = UserDefaults.standard.string(forKey: "orgId") ?? ""
        let ollamaModel = UserDefaults.standard.string(forKey: "ollamaModel") ?? ""
        switch llm {
        case .chatGPT, .chatGPT16k:
            let model = (llm == .chatGPT16k) ? ChatGPT.Model.gpt35_turbo_16k : ChatGPT.Model.gpt35_turbo
            return ChatGPT(credentials: OpenAICredentials(apiKey: key, orgId: orgId), options: .init(model: model, printToConsole: true, printCost: false))
        case .gpt4o:
            return ChatGPT(credentials: OpenAICredentials(apiKey: key, orgId: orgId), options: .init(model: .gpt4_omni, printToConsole: true))
        case .claude:
            return ClaudeNewAPI(credentials: AnthropicCredentials(apiKey: key), options: .init(model: .claude3Haiku, printToConsole: true, responsePrefix: ""))
        case .ollama:
            return ChatGPT(credentials: .init(apiKey: "ollama"), options: .init(model: .custom(ollamaModel, 8192), baseURL: URL(string: "http://localhost:11434/v1/chat/completions")!))
        case .gpt4Vision:
            return ChatGPT(credentials: OpenAICredentials(apiKey: key, orgId: orgId), options: .init(model: .gpt4_vision_preview, maxTokens: 4096, printCost: false))
        case .perplexityOnline7b:
            return PerplexityLLM(credentials: .init(apiKey: key), options: .init(model: .pplx7bOnline))
        case .groq:
            return ChatGPT(credentials: OpenAICredentials(apiKey: key, orgId: orgId), options: .init(temp: 0, model: .custom("deepseek-r1-distill-llama-70b", 32000), maxTokens: 1024, stop: ["|user|:"], baseURL: .groqOpenAIChatEndpoint))
        case .openrouterReasoning:
            return ChatGPT(credentials: OpenAICredentials(apiKey: key, orgId: orgId), options: .init(model: .custom2(ChatGPT.Model.CustomModel(name: "anthropic/claude-3.7-sonnet:thinking", tokenLimit: 128_000, openrouter_reasoning: true)), baseURL: .openRouterOpenAIChatEndpoint))
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
    @AppStorage("bingKey") private var bingKey = ""
    @AppStorage("ollamaModel") private var ollamaModel = ""
    @AppStorage("elevenLabsKey") private var elevenLabsKey = ""

    var body: some View {
        Form {
            Section {
                TextField("API key", text: $key)
                TextField("Organization ID (OpenAI, optional)", text: $orgId)
                TextField("Ollama Model", text: $ollamaModel)
                TextField("ElevenLabs Key", text: $elevenLabsKey)
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
