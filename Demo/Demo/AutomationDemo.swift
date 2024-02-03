import Foundation
import ChatToys
import WebKit
import SwiftUI

struct AutomationDemo: View {
    @StateObject private var automator = Automator()
    @State private var task = ""

    var body: some View {
        VStack {
            Group {
                #if os(macOS)
                AutomatorWebView(automator: automator)
                #else
                Color.red
                #endif
            }

            HStack {
                TextField("Task", text: $task)
                Button("Run") {
                    if task.isEmpty {
                        return
                    }
                    automator.run(task: task)
                    task = ""
                }
            }

            switch automator.status {
            case .none:
                Text("Ready")
            case .running:
                Text("Running")
            case .done(let answer):
                Text("Done: \(answer)")
            case .failed(let error):
                Text("Failed: \(error)")
            }

        }
    }
}

class Automator: ObservableObject {
    let webView = WKWebView()

    enum Status: Equatable {
        case none
        case running
        case done(String)
        case failed(String)
    }

    @Published var status = Status.none

    func run(task: String) {
        //     func automate(task: String, cycles: Int, llm: any ChatLLM) async throws -> String {
        Task {
            DispatchQueue.main.async {
                self.status = .running
            }
            do {
                let llm = LLM.create()
                let answer = try await webView.automate(task: task, cycles: 4, llm: llm)
                DispatchQueue.main.async {
                    self.status = .done(answer)
                }
            }
            catch {
                DispatchQueue.main.async {
                    self.status = .failed(error.localizedDescription)
                }
            }
        }
    }
}

#if os(macOS)
struct AutomatorWebView: NSViewRepresentable {
    var automator: Automator
    func makeNSView(context: Context) -> WKWebView {
        automator.webView.load(.init(url: URL(string: "https://google.com")!))
        automator.webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_5_1) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Safari/605.1.15"
        automator.webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        return automator.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
    }
}

#endif
