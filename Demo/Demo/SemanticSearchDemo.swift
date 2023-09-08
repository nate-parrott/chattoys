import SwiftUI
import ChatToys

struct SemanticSearchDemo: View {
    @State private var text = ""
    @StateObject private var engine = SemanticSearchEngine()

    var body: some View {
        VStack(spacing: 0) {
            ChatThreadView(
                messages: engine.messages,
                id: {_, index in index },
                messageView: { message in
                    TextMessageBubble(Text(message.content), isFromUser: message.role == .user)
                },
                typingIndicator: engine.typing
            )
            Divider()
            ChatInputView(
                placeholder: "Message",
                text: $text,
                sendAction: sendMessage
            )
            RememberButton(engine: engine)
            .padding()
        }
    }

    private func sendMessage() {
        let text = self.text
        self.text = ""
        Task {
            try? await engine.send(message: text)
        }
    }
}

private struct RememberButton: View {
    var engine: SemanticSearchEngine
    @State private var text = "Remember Current Page"

    var body: some View {
        Button(action: {
            self.text = "Working..."
            Task {
                do {
                    try await engine.ingestCurrentPage()
                    DispatchQueue.main.async {
                        self.text = "Saved"
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self.text = "Remember Current Page"
                    }
                } catch {
                    let msg = "Failed to ingest page: \(error)"
                    print("\(msg)")
                    DispatchQueue.main.async {
                        self.text = msg
                    }
                }
            }
        }) {
            Text(text)
        }

    }
}

private class SemanticSearchEngine: ObservableObject {
    @Published var messages = [LLMMessage]()
    @Published var typing = false

    struct PageRecord: Equatable, Codable {
        var title: String
        var url: URL
    }
    let vectorStore: VectorStore<PageRecord>

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = appSupport.appendingPathComponent("semantic-search-demo")
        vectorStore = try! VectorStore<PageRecord>(url: url, embedder: OpenAIEmbedder.create())
    }

    func send(message: String) async throws {
        messages.append(LLMMessage(role: .user, content: message))
        typing = true

        // Fit prompt into context window:
        var prompt = Prompt()

        prompt.append("As a helpful assistant, answer questions using the documents provided.", role: .system, priority: 999)

        let mostRelevantChunks = try await vectorStore.embeddingSearch(query: message, limit: 4)
        for (i, context) in mostRelevantChunks.enumerated() {
            let lines: [String] = [
                "RELEVANT WEBPAGE:",
                "Page title: \(context.data.title)",
                "URL: \(context.data.url.historyKey)",
                "VISITED: \(context.date.formatted())",
                "SNIPPET: \(context.text)"
            ]
            prompt.append(lines.joined(separator: "\n"), role: .system, priority: 50 - Double(i), canTruncateToLength: 300)
        }

        for (i, message) in messages.enumerated() {
            let last5 = i + 5 >= messages.count
            prompt.append(message.content, role: message.role, priority: last5 ? 100 : 10, canOmit: last5, omissionMessage: "[Older messages hidden]")
        }
        let llm = LLM.create()
        let truncatedPrompt = prompt.packedPrompt(tokenCount: llm.tokenLimitWithWiggleRoom)

        Task {
            do {
                var hasAppended = false
                for try await partial in llm.completeStreaming(prompt: truncatedPrompt) {
                    if hasAppended {
                        messages.removeLast()
                    }
                    messages.append(partial)
                    hasAppended = true
                    self.typing = false
                }
            } catch {
                let text = "Error: \(error)"
                messages.append(.init(role: .system, content: text))
                self.typing = false
            }
        }
    }

    // TODO: Do this atomically
    func ingestCurrentPage() async throws {
        guard let title = try await Scripting.arcTitle(),
              let urlStr = try await Scripting.arcURL(),
              let url = URL(string: urlStr),
              let html = try await Scripting.arcHTML()
        else { return }
        let doc = try HTMLProcessor(html: html, baseURL: url)
        let markdown = try doc.convertToMarkdown_doNotUseObjectAfter(hideUrls: false)
        let chunks: [String] = Array(
            markdown.chunkForEmbedding().prefix(4).enumerated()
                .map { tuple in
                    let (i, text) = tuple
                    let lines: [String] = [
                        title.truncate(toTokens: 50),
                        url.historyKey.truncate(toTokens: 30),
                        i == 0 ? "" : "...Part \(i + 1)...",
                        text
                    ]
                    return lines.joined(separator: "\n")
                }
        )
        try await vectorStore.deleteRecords(groups: [url.historyKey])
        let records = chunks.enumerated().map { tuple in
            let (_, text) = tuple
//            let id = "\(url.historyKey):::\(idx)"
            return VectorStore<PageRecord>.Record(id: UUID().uuidString, group: url.historyKey, date: Date(), text: text, data: PageRecord(title: title, url: url))
        }
        try await vectorStore.insert(records: records, deletingOldItemsFromGroup: url.historyKey)
    }
}
