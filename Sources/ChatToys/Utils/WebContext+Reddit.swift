import Foundation

enum RedditWebContextError: Error {
    case invalidURL
}

extension WebContext.Page {
    static func fetchRedditContent(forSearchResult result: WebSearchResult, timeout: TimeInterval, urlMode: FastHTMLProcessor.URLMode) async throws -> WebContext.Page {
        let jsonURL = result.url.appendingPathComponent(".json")
        let data = try await URLSession.shared.data(from: jsonURL).0
        let json = try JSONSerialization.jsonObject(with: data)

        var lines = [String]()
        var indentLevel = 0

        func append(text: String, link: String?, prefix: String = "") {
            let indent = String(repeating: "\t", count: max(0, indentLevel - 1))

            var textLines = text.split(separator: "\n")
            for (i, line) in textLines.enumerated() {
                if i > 0 {
                    textLines[i] = indent + line
                }
            }
            let finalText = textLines.joined(separator: "\n")

            if let link, let url = URL(string: link, relativeTo: result.url), let processedLink = urlMode.process(url: url) {
                lines.append(indent + prefix + "[\(finalText)](\(processedLink))")
            } else {
                lines.append(indent + prefix + finalText)
            }
        }

        func traverse(object: [String: Any]) {
            if let data = object["data"] as? [String: Any] {
                if let author = data["author"] as? String {
                    append(text: author + ":", link: nil)
                    // We don't really need to linkify usernames... not useful info
//                    append(text: "\(author):", link: "https://reddit.com/u/\(author)")
                }

                let link = data["url"] as? String
                if let title = data["title"] as? String {
                    append(text: title, link: link, prefix: "# ")
                }
                if let body = data["body"] as? String {
                    append(text: body, link: nil)
                }

                if let children = data["children"] as? [[String: Any]] {
                    indentLevel += 1
                    for child in children {
                        traverse(object: child)
                    }
                    indentLevel -= 1
                }
            }
        }

        if let obj = json as? [String: Any] {
            traverse(object: obj)
        } else if let objs = json as? [[String: Any]] {
            for obj in objs {
                traverse(object: obj)
            }
        }

        return .init(searchResult: result, markdown: lines.joined(separator: "\n"))
    }
}

