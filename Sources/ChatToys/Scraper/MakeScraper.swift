import Foundation

enum ScraperError: Error {
    case objectIsNotDictionaryOfStrings
    case failedToGenerateRule
}

extension ChatLLM {
    public func makeScraper<T: Codable>(htmlPage: String, baseURL: URL?, example: T, extractName: String = "items", iterations: Int = 1) async throws -> ScraperInstructions<T> {
        var prompt = Prompt()
        let structureExample = try example.prettyPrintedByReplacingAllFieldsWithEmptyString()
        let fieldNames = try example.fieldNames()
        guard let firstFieldName = fieldNames.first else {
            throw ScraperError.objectIsNotDictionaryOfStrings
        }

        let fieldSelectors = fieldNames.map { name in
            "\"\(name)\": \"...\""
        }.joined(separator: ", ")

        let simplifiedHtml = htmlPage.simplifyHTML(truncateTextNodes: 200) ?? htmlPage
        prompt.append("HTML page:\n\(simplifiedHtml)", role: .user, canTruncateToLength: 1000)

        prompt.append("""
I'd like you to write an `ExtractionRule` to help me extract \(extractName) from the webpage above.

The \(extractName) I want to extract should be structured like this:
```
\(structureExample)
```

An `ExtractionRule` is a JSON bundle containing CSS selectors that tell my program how to extract each field of each item.

Here is what an extractionRule looks like:
```
{
    // fieldSelectors is a mapping of field names (e.g. \(firstFieldName)) to the CSS selectors that would match them.
    // (write 'unknown' for the selector if you don't see the requested field on the page)
    "fieldSelectors": { \(fieldSelectors) },

    // fieldAttributes is a mapping of field names (e.g. \(firstFieldName)) to the attribute of the matched element that we should extract.
    // valid values are "innerText", "value", "src", "href". "unknown" if you can't find an attribute that provides this info.
    "fieldAttributes": { \(fieldSelectors) },

    // firstField is the name of the field (not the selector) that appears first (or highest) in the HTML. This tells my program when a new item starts.
    "firstField": "...",

    // excludeSelectors is an array of CSS selectors whose content we should ignore. optional.
    "excludeSelectors": [],
}
```

Output only two things:
1. First, write bullet points describing a few CSS selectors that you'd use to reference each field. Try to choose STABLE, SEMANTIC selectors, if possible, so that my program does not break if the website changes slightly. (e.g. rules like '.content h1' are good, '.css_23823' are bad)
2. Then, write an extraction rule within a ```code block```.
""", role: .user)

        guard let json = try? await completeJSONObject(prompt: prompt.packedPrompt(tokenCount: tokenLimitWithWiggleRoom), type: AnyScraperInstructions.self) else {
            throw ScraperError.failedToGenerateRule
        }
        var instructions = ScraperInstructions<T>(base: json)

        for _ in 0..<(iterations - 1) {
            prompt.append("```\(instructions.base.jsonString)```", role: .assistant)
            var result: String = ""
            do {
                result = try instructions.extract(fromHTML: htmlPage, baseURL: baseURL).jsonString.truncate(toTokens: 400)
            } catch {
                result = "Error: \(error)"
            }
            prompt.append("""
OK, here's the result:
```
\(result)
```
Do you want to refine your answer?
Output only the refined extraction rule (or the same one, if it was good beforee) below, in a ```code block```:
""", role: .user)
            if let result = try? await completeJSONObject(prompt: prompt.packedPrompt(tokenCount: tokenLimitWithWiggleRoom), type: AnyScraperInstructions.self) {
                instructions = .init(base: result)
            } else {
                break
            }
        }

        return instructions
    }
}

private extension Encodable {
    func fieldNames() throws -> [String] {
        let data = try JSONEncoder().encode(self)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw ScraperError.objectIsNotDictionaryOfStrings
        }
        return Array(dict.keys)
    }

    func prettyPrintedByReplacingAllFieldsWithEmptyString() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard var dict = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw ScraperError.objectIsNotDictionaryOfStrings
        }
        for key in dict.keys {
            dict[key] = ""
        }
        let finalData = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
        return String(data: finalData, encoding: .utf8)!
    }
}


//public struct AnyScraperInstructions: Codable {
//    public var fieldSelectors: [String: String] // maps field name -> selector
//    public var fieldAttributes: [String: FieldAttribute]?
//    public var firstField: String
//    public var excludeSelectors: [String]
//
//    public enum FieldAttribute: String, Codable {
//        case innerText
//        case value
//        case src
//        case href
//    }
//}
