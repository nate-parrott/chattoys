import SwiftSoup

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

                // If there's a single <article>, return it
                let articles = try doc.select("article")
                if articles.count == 1 {
                    return try articles.first()?.outerHtml()
                }
            }
            
            return try doc.body()?.outerHtml()
        } catch {
            return nil
        }
    }
}
