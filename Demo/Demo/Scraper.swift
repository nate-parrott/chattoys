import SwiftUI
import ChatToys

struct Scraper: View {
    @State private var url = "https://news.ycombinator.com/"

    struct Item: Codable, Identifiable {
        var title: String
        var link: String
        var subtitle: String?
        var image: String?

        var id: String { link }
    }
    @State private var items: [Item]?
    @State private var errorMessage: String?
    @State private var running = false
    @State private var scraper: ScraperInstructions<Item>?

    var body: some View {
        Form {
            Section {
                TextField("URL", text: $url)
            }
            Section {
                Button("Make scraper (1 iteration)", action: { scrape(iterations: 1) })
                .disabled(running)

                Button("Make scraper (2 iterations)", action: { scrape(iterations: 2) })
                .disabled(running)


                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
                if let scraper {
                    JsonView(object: scraper)
                }
            }

            Section {
                if let items {
                    ForEach(items) { item in
                        ItemView(item: item)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func scrape(iterations: Int) {
        guard let url = URL(string: url) else {
            errorMessage = "Invalid URL"
            return
        }
        errorMessage = nil
        items = nil
        scraper = nil

        Task {
            self.running = true
            defer { self.running = false }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let html = String(data: data, encoding: .utf8)!
                let llm = LLM.create()
                let scraper = try await llm.makeScraper(htmlPage: html, baseURL: url, example: Item(title: "", link: "", subtitle: "", image: ""), iterations: iterations)
                self.scraper = scraper
                self.items = try scraper.extract(fromHTML: html, baseURL: url)
            } catch {
                errorMessage = "\(error)"
            }
        }
    }

    private struct ItemView: View {
        var item: Item

        @Environment(\.openURL) var openURL

        var body: some View {
            HStack {
                URLImageView(url: item.image ?? "")
                VStack(alignment: .leading) {
                    Text(item.title)
                    if let sub = item.subtitle {
                        Text(sub).font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                openURL(URL(string: item.link)!)
            }
        }
    }
}

private struct URLImageView: View {
    var url: String

    var body: some View {
        AsyncImage(url: URL(string: url)) { image in
                image.resizable()
                .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.primary.opacity(0.1)
            }
        .frame(width: 50, height: 50)
        .cornerRadius(10)
        .clipped()
    }
}

private struct JsonView<T: Encodable>: View {
    var object: T

    var body: some View {
        CodeView(text: object.jsonString)
    }
}

private struct CodeView: View {
    var text: String

    var body: some View {
        Text(text)
            .foregroundColor(.white)
            .font(.system(.body, design: .monospaced))
            .padding()
            .background(Color(.black))
            .cornerRadius(10)
    }
}
