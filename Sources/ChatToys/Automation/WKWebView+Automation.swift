import WebKit
import Foundation

struct AutomationOutput: Codable {
    let taskPlan: String
    let thought: String
    let action: AutomationAction
    let expectedResult: String
}

enum AutomationError: Error {
    case invalidAction
    case unsupportedAction
    case tooManyCycles
}

struct AutomationAction: Codable {
    let kind: String // click | navigate | back | setValue | finish
    let id: String? // kind: click, setValue
    let query: String? // kind: navigate
    
    let value: String? // kind: setValue

    let success: Bool? // kind: finish
    let comment: String? // kind: finish

    enum ParsedKind: String, Codable {
        case click, navigate, back, setValue, finish
    }

    var textualDescription: String {
        switch kind {
        case "click":
            return "Click \(id ?? "")"
        case "navigate":
            return "Navigate to \(query ?? "")"
        case "back":
            return "Go back"
        case "setValue":
            return "Set \(id ?? "") to \(value ?? "")"
        case "finish":
            return "Finish with \(success == true ? "success" : "failure"): \(comment ?? "")"
        default:
            return "Unknown action"
        }
    }

    @MainActor
    func apply(to webView: WKWebView) async throws {
        guard let kind = ParsedKind(rawValue: kind) else {
            throw AutomationError.invalidAction
        }
        switch kind {
        case .click:
            guard let id = id else {
                throw AutomationError.invalidAction
            }
            _ = try await webView.fixed_evaluateJavascript("""
            const element = window.__automationIdMap[\(id)];
            if (!element) {
                throw new Error('No element with ID \(id)');
            }
            element.click();
            """.wrappedInJSFunctionCall)
            try await webView.waitUntilLoaded()
        case .navigate:
            guard let query = query else {
                throw AutomationError.invalidAction
            }
            webView.load(URLRequest(url: URL.withSearchQuery(query)))
            try await webView.waitUntilLoaded()
        case .back:
            webView.goBack()
            try await webView.waitUntilLoaded()
        case .setValue:
            throw AutomationError.unsupportedAction
        case .finish: ()
        }
    }
}

extension WKWebView {
    @MainActor
    func waitUntilLoaded() async throws {
        try await Task.sleep(seconds: 0.5)
        while isLoading {
            try await Task.sleep(seconds: 0.5)
        }
    }

    @MainActor
    public func automate(task: String, cycles: Int, llm: any ChatLLM) async throws -> String {

        var lastOutput: AutomationOutput?

        var steps = [String]()

        for _ in 0..<cycles {

            let prevPlan: String
            if let lastOutput {
                prevPlan = """
                You are continuing an autonomous browsing session performed by another robot. It already started on this task. It wrote this plan: '\(lastOutput.taskPlan)'.
                It previously performed these steps:
                \(steps.map { " - " + $0 }.joined(separator: "\n"))
                After performing its last action, it expected to have this effect:
                '\(lastOutput.expectedResult)'
                """
            } else {
                prevPlan = ""
            }

            let content = try await automatablePage()
//            print("AUTOMATION CONTENT:\n\(content)")

            let prompt = """
            You are browsing the internet autonomously to perform a user's task. You can navigate, click links, fill in forms and click buttons to interact with a site.

            Your task: '\(task)'
            Today's date: '\(Date.formattedDateAndTime)'
            Current URL: \((url?.absoluteString ?? "").truncateTail(maxLen: 100))

            Below, I'll show you the content of the current page. Interact with interactive elements using their ID.
            Clickable buttons look like this: [[ID]], e.g. [[Submit]].
            Clickable links look like this: [ID].
            Editable text fields looks like this: <ID|Current text>.
            Selectable menu items and radio buttons look like this: {ID|selected} or {ID|} for deselected.
            Checkboxes look like this: {ID [x]} or {ID []}.
            There will also be plain text.

            BEGIN PAGE CONTENT
            \(title ?? "")
            \(content.truncate(toTokens: Int(Double(llm.tokenLimit) * 0.5)))
            END PAGE CONTENT

            \(prevPlan)

            Now, you'll write a NEW plan for completing the task (or reuse the existing one, if it was good). Then, you'll output the next action to take, using this JSON `Output` schema:

            ```
            interface Output {
                taskPlan: string // concise plan for accomplishing the task from beginning to end.
                thought: string // what do you need to do NOW to make progress? Did previous actions (if any) have the expected effect?
                action: Click | Navigate | Back | SetValue | Finish
                expectedResult: string // what do you expect to see?

            }

            interface Click {
                kind: 'click'
                id: string
            }

            interface Navigate {
                kind: 'navigate'
                query: string // search query or URL
            }

            interface Back {
                kind: 'back'
            }

            interface SetValue {
                kind: 'setValue' // use to set a text field's value, select an element, or do something else
                id: string
                value: string // text value, for text fields. "checked" or "unchecked" for checkboxes. "selected" for radio buttons or menu items.
            }

            interface Finish {
                kind: 'finish'
                success: boolean
                comment: string // give the user their answer, explain what you did, or tell me why you failed.
            }
            ```

            Make sure your response is in json!
            """

//            print("AUTOMATION:\n\(prompt)")

            let output = try await llm.completeJSONObject(prompt: [.init(role: .assistant, content: prompt)], type: AutomationOutput.self)
            lastOutput = output
            print("AUTOMATION ACTION:\n\(output.action.jsonString)")
            try await output.action.apply(to: self)
            steps.append(output.action.textualDescription)
            if output.action.kind == "finish" {
                return output.action.comment ?? ""
            }
        }
        throw AutomationError.tooManyCycles
    }
}

extension Date {
    static var formattedDateAndTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }
}

private extension WKWebView {
    func automatablePage() async throws -> String {
        let js = """
        function automatablePage() {
            let shouldOutputTextNodesStack = 0; // if >1, will output text nodes
            let results = [];

            window.__automationIdMap = {};

            function traverse(node) {
                if (node.nodeType === Node.TEXT_NODE) {
                    // if (shouldOutputTextNodesStack > 0) {
                        results.push(node.textContent);
                    // }
                } else if (node.nodeType === Node.ELEMENT_NODE) {
                    const tag = node.tagName.toLowerCase();
                    const style = window.getComputedStyle(node);
                    const isHidden = style.display === 'none' || style.visibility === 'hidden';
                    if (isHidden) {
                        return;
                    }
                    const skippableTags = ['script', 'svg', 'style', 'link', 'meta', 'head', 'html'];
                    if (skippableTags.includes(tag)) {
                        return;
                    }
                    const nodeId = node.placeholder || node.innerText || node.value || node.id || node.name || node.title || node.alt || node.textContent;
                    if (tag === 'input') {
                        const valueTypes = ['text', 'email', 'address', 'tel', 'url', 'search', 'password'];
                        const type = node.getAttribute('type');
                        if (valueTypes.includes(type)) {
                            results.push(`<${nodeId}|${node.value}>`);
                        } else if (type === 'checkbox') {
                            results.push(`{${nodeId} [${node.checked ? 'x' : ' '}]}`);
                        } else if (type === 'radio') {
                            results.push(`{${nodeId} [${node.checked ? 'x' : ' '}]}`);
                        }
                        __automationIdMap[nodeId] = node;
                    } else if (tag === 'option') {
                        const isSelected = node.selected;
                        results.push(`{${nodeId}|${isSelected ? 'selected' : ''}}`);
                        __automationIdMap[nodeId] = node;
                    } else if (tag === 'textarea') {
                        results.push(`<${nodeId}|${node.value}>`);
                        __automationIdMap[nodeId] = node;
                    } else if (tag === 'button') {
                        results.push(`[[${nodeId}]]`);
                        __automationIdMap[nodeId] = node;
                    } else if (tag === 'a') {
                        results.push(`[${nodeId}]`);
                        __automationIdMap[nodeId] = node;
                    } else {
                        // We will traverse children now
                        const textualTags = ['p', 'label', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li' ];
                        const isTextual = textualTags.includes(tag);
                        if (isTextual) {
                            shouldOutputTextNodesStack += 1;
                        }
                        // Traverse children
                        for (const child of node.childNodes) {
                            traverse(child);
                        }
                        // Pop stack
                        if (isTextual) {
                            shouldOutputTextNodesStack -= 1;
                        }
                    }
                }
            }
            traverse(document.body);
            // Trim whitespace and filter empty
            results = results.map(s => s.trim()).filter(s => s.length > 0);
            return results.join('\\n');
        }
        try {
            return automatablePage();
        } catch (e) {
            return e.toString();
        }
        """
        //     func evaluateJavascript<ResponseType: Decodable>(_ script: String, withReturnType: ResponseType.Type) async throws -> ResponseType {

        return try await evaluateJavascript(js.wrappedInJSFunctionCall, withReturnType: String.self)
    }
}

extension URL {
    static func withSearchQuery(_ searchQuery: String) -> URL {
        return withNaturalString(searchQuery) ?? googleSearch(searchQuery)
    }

    static func googleSearch(_ query: String) -> URL {
        var comps = URLComponents(string: "https://google.com/search")!
        comps.queryItems = [URLQueryItem(name: "q", value: query)]
        return comps.url!
    }

    static func withNaturalString(_ string: String) -> URL? {
        if !(string.contains(":") || string.contains(".")) {
            return nil
        }
        if stringHasURLScheme(string) {
            return URL(string: string)
        }
        return URL(string: "https://" + string)
    }
}

private func stringHasURLScheme(_ str: String) -> Bool {
    if let comps = URLComponents(string: str) {
        return comps.scheme?.count ?? 0 > 0
    }
    return false
}
