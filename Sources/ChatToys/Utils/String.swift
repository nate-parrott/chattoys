import Foundation

extension String {
    var nilIfEmpty: String? {
        return isEmpty ? nil : self
    }

    var nilIfEmptyOrJustWhitespace: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func truncateTail(maxLen: Int) -> String {
        if count + 3 > maxLen {
            if maxLen <= 3 {
                return ""
            }
            return prefix(maxLen - 3) + "..."
        }
        return self
    }

    func removing(prefix: String) -> String {
        if hasPrefix(prefix) {
            return String(dropFirst(prefix.count))
        }
        return self
    }
    func removing(suffix: String) -> String {
        if hasSuffix(suffix) {
            return String(dropLast(suffix.count))
        }
        return self
    }

    func containsOnlyCharacters(fromSet charSet: CharacterSet) -> Bool {
        trimmingCharacters(in: charSet) == ""
    }

    func first(nChars n: Int) -> String {
        return String(prefix(n))
    }

    var firstLine: String {
        return components(separatedBy: .newlines).first ?? self
    }

    var asDouble: Double? {
        return Double(self)
    }

    var asJSString: String {
        let data = try! JSONSerialization.data(withJSONObject: self, options: .fragmentsAllowed)
        return String(data: data, encoding: .utf8)!
    }

    var trimWhitespaceAroundNewlines: String {
        return self.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { line in
                return line.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { $0 != "" }
            .joined(separator: "\n")
    }

    var dropLastLine: String {
        var lines = split(separator: "\n")
        if lines.count > 0 {
            _ = lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}
