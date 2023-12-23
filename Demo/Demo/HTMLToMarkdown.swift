import SwiftUI
import ChatToys

struct HTMLToMarkdownDemo: View {
    @State private var urlInput = ""
    
    enum Result {
        case none
        case loading
        case fetched(String)
        case error(Error)
    }

    @State private var result: Result = .none

    var body: some View {
        ScrollView {
            Form {
                Section {
                    TextField("URL", text: $urlInput)
                    Button("Fetch") {
                        guard let url = URL(string: urlInput) else { return }
                        result = .loading
                        Task {
                            do {
                                let markdown = try await WebContext.Page.fetch(forSearchResult: .init(url: url, title: "", snippet: nil), timeout: 5, urlMode: .truncate(20)).markdown
//                                let (data, resp) = try await URLSession.shared.data(from: url)
//                                let markdown = try await FastHTMLProcessor(url: resp.url ?? url, data: data).markdown(urlMode: .truncate(50))
                                result = .fetched(markdown)
                            } catch {
                                result = .error(error)
                            }
                        }
                    }
                }
                Section {
                    switch result {
                    case .none:
                        EmptyView()
                    case .loading:
                        ProgressView()
                    case .fetched(let markdown):
                        Text(markdown)
                        .font(.system(.callout, design: .monospaced))
                        .background(Color.black)
                        .foregroundColor(.white)
                        .lineLimit(nil)
                    case .error(let error):
                        Text(error.localizedDescription)
                    }
                }
            }
        }
    }

}
