import SwiftSoup
import Foundation

extension String {
    public func simplifyHTML(truncateTextNodes: Int?, contentOnly: Bool = false) -> String? {
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

            try doc.select("[aria-hidden=true]").remove()

            if contentOnly {
                // Remove navigation
                try doc.select("nav, [aria-role=navigation]").remove()
                // Remove footer
                try doc.select("footer").remove()
                // Remove header
                try doc.select("header").remove()
                try doc.select("[aria-role=banner]").remove()
                // Remove form
                try doc.select("form").remove()
                // Remove alerts
                try doc.select("[arial-role=alert]").remove()
                // Remove dialogs
                try doc.select("[arial-role=dialog]").remove()

                let contentSelectors = ["[itemprop=mainEntity]", "article", "#content"]
                for selector in contentSelectors {
                    let matches = try doc.select(selector)
                    if matches.count == 1 {
                        return try matches.first()?.outerHtml()
                    }
                }
            }
            
            return try doc.body()?.outerHtml()
        } catch {
            return nil
        }
    }

    public func htmlToMarkdown(hideUrls: Bool = false) throws -> String {
        // Parse doc
        let doc = try SwiftSoup.parse(self)

        // Use UUID as token, then sub it for a linebreak at the end
        let linebreak = UUID().uuidString
        
        struct Rule {
            var prefix: String?
            var suffix: String?
        }
        let rules: [String: Rule] = [
            "h1": Rule(prefix: "\(linebreak)# ", suffix: linebreak),
            "h2": Rule(prefix: "\(linebreak)## ", suffix: linebreak),
            "h3": Rule(prefix: "\(linebreak)### ", suffix: linebreak),
            "h4": Rule(prefix: "\(linebreak)#### ", suffix: linebreak),
            "h5": Rule(prefix: "\(linebreak)##### ", suffix: linebreak),
            "h6": Rule(prefix: "\(linebreak)###### ", suffix: linebreak),
            "em": Rule(prefix: "_", suffix: "_"),
            "strong": Rule(prefix: "**", suffix: "**"),
            "br": Rule(prefix: nil, suffix: linebreak),
            "p": Rule(prefix: linebreak, suffix: linebreak),
            "li": Rule(prefix: "\(linebreak)- ", suffix: linebreak),
            "blockquote": Rule(prefix: "\(linebreak)> ", suffix: linebreak),
            "code": Rule(prefix: "``", suffix: "`"),
        ]

        // Apply rules
        for (tag, rule) in rules {
            for el in try doc.select(tag) {
                if let prefix = rule.prefix {
                    try el.before(prefix)
                }
                if let suffix = rule.suffix {
                    try el.after(suffix)
                }
            }
        }

        // Handle links
        for el in try doc.select("a") {
            if let text = try? el.text().nilIfEmpty {
                if !hideUrls, let href = try? el.attr("href") {
                    try el.text("[\(text)](\(href))")
                } else {
                    try el.text("[\(text)]")
                }
            }
        }
        // Handle images
        for el in try doc.select("img") {
            // for inner text, use alt
            if let alt = try? el.attr("alt") {
                if let url = try? el.attr("src").nilIfEmpty, !hideUrls {
                    try el.text("![\(alt)](\(url))")
                } else {
                    try el.text("![\(alt)]")
                }
            }
        }

        // TODO: Keep original indentation
        for el in try doc.select("pre") {
            if let text = try? el.text().nilIfEmpty {
                let textWithLinebreaks = text.components(separatedBy: "\n").joined(separator: linebreak + "    ")
                try el.text("\(linebreak)```\(linebreak)\(textWithLinebreaks)\(linebreak)```\(linebreak)")
            }
        }

        let parts = try doc.text()
            .components(separatedBy: linebreak)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ") }
            .compactMap { $0.nilIfEmpty }

        return parts.joined(separator: "\n")
    }
}
