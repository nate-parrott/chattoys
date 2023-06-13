import SwiftSoup

extension String {
//    var htmlToPlain: String {
//        do {
//            let doc = try HTMLDocument(string: self)
//            return (doc.root?.stringValue.trimWhitespaceAroundNewlines ?? self)
//        }
//        catch {
//            return self
//        }
//    }

//    var trimWhitespaceAroundNewlines: String {
//        return self.trimmingCharacters(in: .whitespacesAndNewlines)
//            .components(separatedBy: .newlines)
//            .map { line in
//                return line.trimmingCharacters(in: .whitespacesAndNewlines)
//            }
//            .filter { $0 != "" }
//            .joined(separator: "\n")
//    }

    public func simplifyHTML(truncateTextNodes: Int?) -> String? {
        // Use beautifulsoup to simplify html
        // Remove script and style tags.
        // Remove imagesrcset attr
        // Shorten URLs
        // Remove HTML comments
        do {
            let doc = try SwiftSoup.parse(self)
            try doc.select("script, style, link, svg").remove()
            try doc.select("[srcset]").removeAttr("srcset")
            doc.outputSettings().prettyPrint(pretty: false).syntax(syntax: .html)
            
            // Truncute src attributes to 500 chars:
            for el in try doc.select("[src]") {
                if let src = try? el.attr("src") {
                    if src.count > 500 {
                        try el.attr("src", src.prefix(500) + "...")
                    }
                }
            }

            if let truncateTextNodes {
                for el in try doc.select("*") {
                    if el.children().count == 0, let text = try? el.text() {
                        if text.count > truncateTextNodes {
                            try el.text(text.prefix(truncateTextNodes) + "...")
                        }
                    }
                }
            }
            
            return try doc.body()?.outerHtml()
        } catch {
            return nil
        }
    }
}
