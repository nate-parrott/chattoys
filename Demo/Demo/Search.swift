import SwiftUI
import ChatToys

struct SearchDemo: View {
    @State private var query = ""
    @State private var results = [WebSearchResult]()
    @State private var error: String?

    var body: some View {
        Form {
            Section(header: Text("Search")) {
                TextField("Query", text: $query)
                Button("Search") {
                    submit()
                }
            }
            .onSubmit {
                submit()
            }

            if let error = error {
                Section(header: Text("Error")) {
                    Text(error)
                }
            }

            Section(header: Text("Results")) {
                ForEach(results, id: \.url) { result in
                    ResultCell(result: result)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func submit() {
        Task {
            do {
                self.error = nil
                results = try await GoogleSearchEngine().search(query: query)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct ResultCell: View {
    let result: WebSearchResult

    var body: some View {
        Link(destination: result.url) {
            VStack(alignment: .leading) {
                Text(result.url.host ?? "?")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Text(result.title)
                    .font(.headline)
                if let snippet = result.snippet {
                    Text(snippet)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
        }
    }
}