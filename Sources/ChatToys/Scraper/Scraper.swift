import Foundation
import Fuzi

public struct AnyScraperInstructions: Codable {
    public var fieldSelectors: [String: String] // maps field name -> selector
    public var fieldAttributes: [String: FieldAttribute]?
    public var firstField: String
    public var excludeSelectors: [String]

    public enum FieldAttribute: String, Codable {
        case innerText
        case value
        case src
        case href
    }
}

public struct ScraperInstructions<Item: Codable> {
    public var base: AnyScraperInstructions
}

extension ScraperInstructions {
    public func extract(fromHTML html: String, baseURL: URL?) throws -> [Item] {
        var items = [Item]()
        var currentItemFields = [String: String]()

        let doc = try HTMLDocument(string: html)

        typealias E = Fuzi.XMLElement

        // Delete excluded selectors
        for selector in base.excludeSelectors {
            for el in doc.css(selector) {
                el.parent.remov
            }
        }

        // TODO: Find a faster way of looking up elements than equality
        var elementsMatchingField = [String: [E]]()
        for (field, selector) in base.fieldSelectors {
//            var els = [Fuzi.XMLElement]()
//            for element in doc.css(selector) {
//                allElements.append(element)
//            }
            elementsMatchingField[field] = Array(doc.css(selector))
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
            currentItemFields[field] = value
        }

        try doc.body?.iterateAllElements(block: { element in
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

private extension Fuzi.XMLElement {
    func value(fieldAttribute: AnyScraperInstructions.FieldAttribute, baseURL: URL?) -> String? {
        switch fieldAttribute {
        case .value:
            return attributes["value"]
        case .href:
            return urlAttribute(name: "href", baseURL: baseURL)
        case .src:
            return urlAttribute(name: "src", baseURL: baseURL)
        case .innerText:
            return self.stringValue.trimWhitespaceAroundNewlines // TODO: make sure we preserve internal newlines properly
        }
    }

    private func urlAttribute(name: String, baseURL: URL?) -> String? {
        if let val = attributes[name] {
            return URL(string: val, relativeTo: baseURL)?.absoluteString
        }
        return nil
    }

    // return true if should recur
    func iterateAllElements(block: (Fuzi.XMLElement) throws -> Bool) throws {
        let recur = try block(self)
        if recur {
            for child in children {
                try child.iterateAllElements(block: block)
            }
        }
    }
}
