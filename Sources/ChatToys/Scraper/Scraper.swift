import Foundation
import SwiftSoup

public struct AnyScraperInstructions: Codable {
    public var fieldSelectors: [String: String] // maps field name -> selector
    public var fieldAttributes: [String: FieldAttribute]?
    public var firstField: String
    public var excludeSelectors: [String]?

    public enum FieldAttribute: String, Codable {
        case innerText
        case value
        case src
        case href
        case unknown
    }
}

public struct ScraperInstructions<Item: Codable>: Codable {
    public var base: AnyScraperInstructions
}

extension ScraperInstructions {
    public func extract(fromHTML html: String, baseURL: URL?) throws -> [Item] {
        var items = [Item]()
        var currentItemFields = [String: String]()

        let doc = try SwiftSoup.parse(html, baseURL?.absoluteString ?? "")

        typealias E = SwiftSoup.Element

        // Delete excluded selectors
        for selector in base.excludeSelectors ?? [] {
            for el in try doc.select(selector) {
                try el.remove()
            }
        }

        var elementsMatchingField = [String: Set<E>]()
        for (field, selector) in base.fieldSelectors {
            elementsMatchingField[field] = try Set(doc.select(selector))
        }

        let fieldsForElement: (E) -> [String] = { el in
            return elementsMatchingField.compactMap { pair in
                let (field, elements) = pair
                if elements.contains(el) {
                    return field
                }
                return nil
            }
        }

        let finishCurrentItem = {
            let encoded = try JSONSerialization.data(withJSONObject: currentItemFields)
            if let decoded = try? JSONDecoder().decode(Item.self, from: encoded) {
                items.append(decoded)
            }
            currentItemFields.removeAll()
        }

        let gotFieldValue = { (field: String, value: String) in
            if field == base.firstField {
                try finishCurrentItem()
            }
            if currentItemFields[field] == nil {
                currentItemFields[field] = value
            }
        }

        try doc.body()?.iterateAllElements(block: { element in
            for field in fieldsForElement(element) {
                let fieldAttr = base.fieldAttributes?[field] ?? .innerText
                if let value = element.value(fieldAttribute: fieldAttr, baseURL: baseURL) {
                    try gotFieldValue(field, value)
                }
            }
            return true
        })

        try finishCurrentItem()
        return items
    }
}

private extension SwiftSoup.Element {
    func value(fieldAttribute: AnyScraperInstructions.FieldAttribute, baseURL: URL?) -> String? {
        switch fieldAttribute {
        case .value:
            return safeAttr("value")
        case .href:
            return urlAttribute(name: "href", baseURL: baseURL)
        case .src:
            return urlAttribute(name: "src", baseURL: baseURL)
        case .innerText:
            return try? self.text(trimAndNormaliseWhitespace: true)
        case .unknown: return nil
        }
    }

    private func safeAttr(_ key: String) -> String? {
        do {
            return try attr(key)
        } catch {
            return nil
        }
    }

    private func urlAttribute(name: String, baseURL: URL?) -> String? {
        if let val = safeAttr(name) {
            return URL(string: val, relativeTo: baseURL)?.absoluteString
        }
        return nil
    }

    // return true if should recur
    func iterateAllElements(block: (SwiftSoup.Element) throws -> Bool) throws {
        let recur = try block(self)
        if recur {
            for child in children() {
                try child.iterateAllElements(block: block)
            }
        }
    }
}
