import SwiftUI
import ChatToys

struct SearchDemo: View {
    @State private var query = ""
    @State private var committedQuery: String?
    @AppStorage("engine") private var engine = Engine.googleWeb
    @AppStorage("bingKey") private var bingKey = ""

    enum Engine: String, CaseIterable, Hashable {
        case googleWeb
        case bingWeb
        case googleImages
        case bingImages
    }

    var body: some View {
        Form {
            Section(header: Text("Search")) {
                TextField("Query", text: $query)
                enginePicker
                Button("Search") {
                    submit()
                }
            }
            .onSubmit {
                submit()
            }
            resultsView
        }
        .formStyle(.grouped)
    }

    private func submit() {
        committedQuery = query
    }

    private var enginePicker: some View {
        Picker("Engine", selection: $engine) {
            ForEach(Engine.allCases, id: \.self) { engine in
                Text(engine.rawValue)
                    .tag(engine)
            }
        }
    }

    @ViewBuilder private var resultsView: some View {
        if let query = committedQuery {
            Group {
                switch engine {
                case .googleWeb:
                    WebSearchDemoView(query: query, engine: GoogleSearchEngine())
                case .bingWeb:
                    WebSearchDemoView(query: query, engine: BingSearchEngine(apiKey: bingKey))
                case .googleImages:
                    ImageSearchDemoView(query: query, engine: GoogleImageSearchEngine())
                case .bingImages:
                    ImageSearchDemoView(query: query, engine: BingSearchEngine(apiKey: bingKey))
                }
            }
                .id(query)
        }
    }
}

private struct WebSearchDemoView: View {
    var query: String
    var engine: any WebSearchEngine

    @State private var result: Result?

    enum Result {
        case results([WebSearchResult])
        case error(Error)
    }

    var body: some View {
        Section {
            if let result {
                switch result {
                case .results(let results):
                    ForEach(results, id: \.url) { result in
                        WebResultCell(result: result)
                    }
                case .error(let error):
                    Text(error.localizedDescription)
                }
            } else {
                ProgressView()
            }
        }
        .task(id: query) {
            result = nil
            do {
                result = .results(try await engine.search(query: query).results)
            } catch {
                result = .error(error)
            }
        }
    }
}

private struct ImageSearchDemoView: View {
    var query: String
    var engine: any ImageSearchEngine

    @State private var result: Result?

    enum Result {
        case images([ImageSearchResult])
        case error(Error)
    }

    var body: some View {
        Section {
            if let result {
                switch result {
                case .images(let images):
                    ForEach(images, id: \.id) { image in
                        ImageSearchResultCell(result: image)
                    }
                case .error(let error):
                    Text(error.localizedDescription)
                }
            } else {
                ProgressView()
            }
        }
        .task(id: query) {
            result = nil
            do {
                result = .images(try await engine.searchImages(query: query))
            } catch {
                result = .error(error)
            }
        }
    }
}

private struct ImageSearchResultCell: View {
    let result: ImageSearchResult

    var body: some View {
        Link(destination: result.hostPageURL) {
            HStack {
                Thumbnail(url: result.thumbnailURL ?? result.imageURL)
                if let size = result.size {
                    Text("\(size.width) x \(size.height)")
                }
//                Text(result.hostPageURL.absoluteString)
//                    .font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
        }
    }
}

private struct Thumbnail: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Color.gray
        }
        .frame(width: 50, height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private struct WebResultCell: View {
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
