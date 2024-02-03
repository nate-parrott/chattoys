import WebKit

enum HTMLError: Error {
    case cantGetHTML
}

private enum WebViewJSError: Error {
    case noResult
    case wrongOutputType
}


public extension HTMLProcessor {
    static func fromWebView(_ webView: WKWebView) async throws -> HTMLProcessor {
        guard let html = try await webView.fixed_evaluateJavascript("document.body.outerHTML") as? String else {
            throw HTMLError.cantGetHTML
        }
        let url = await webView.url
        return try .init(html: html, baseURL: url)
    }
}

extension WKWebView {
    func fixed_evaluateJavascript(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.main.async {
                self.evaluateJavaScript(script) { resultOpt, errOpt in
                    if let errOpt {
                        cont.resume(throwing: errOpt)
                        return
                    }
                    cont.resume(returning: resultOpt)
                }
            }
        }
    }

    func evaluateJavascript<ResponseType: Decodable>(_ script: String, withReturnType: ResponseType.Type) async throws -> ResponseType {
        guard let untypedJson = try await fixed_evaluateJavascript(script) else {
            throw WebViewJSError.wrongOutputType
        }
        let data = try JSONSerialization.data(withJSONObject: untypedJson, options: .fragmentsAllowed)
        return try JSONDecoder().decode(ResponseType.self, from: data)
    }
}

extension String {
    var wrappedInJSFunctionCall: String {
        return "(function() {\(self)})()"
    }
}
