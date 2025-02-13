import Foundation
import WebKit

extension WKWebView {
    /// Gets the current page content as markdown
    /// - Parameter urlMode: How to handle URLs in the output. Defaults to .keep
    /// - Returns: The page content converted to markdown
    @MainActor
    public func markdown(urlMode: FastHTMLProcessor.URLMode = .keep) async throws -> String {
        // Get the HTML content on main thread
        let html = try await evaluateJavaScript("document.documentElement.outerHTML") as? String ?? ""
        let url = self.url
        guard let url else {
            return ""
        }
        
        // Process the HTML into markdown on background thread
        return try await DispatchQueue.global().performAsyncThrowing {
            let processor = try FastHTMLProcessor(url: url, data: html.data(using: .utf8)!) // FastHTMLProcessor(html: html, baseURL: url)
            return try processor.markdown(urlMode: urlMode, hideImages: false, moveJsonLDToFront: false)
        }
    }
}
