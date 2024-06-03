import Foundation

public extension Encodable {
    var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try! encoder.encode(self)
        return String(data: data, encoding: .utf8)!
    }
    var jsonStringNotPretty: String {
        let encoder = JSONEncoder()
        let data = try! encoder.encode(self)
        return String(data: data, encoding: .utf8)!
    }

}

extension Array {
    var nilIfEmptyArray: Self? {
        isEmpty ? nil : self
    }
}

extension String {
    public var byExtractingOnlyCodeBlocks: String {
        var s = self.trimmed
        if !s.starts(with: "```") {
            return self
        }
        for separator in ["```", "`"] {
            let parts = s.components(separatedBy: separator)
            if parts.count == 1 {
                continue
            }
            let code = parts.enumerated().filter { $0.offset % 2 == 1 }.map { $0.element }.joined(separator: "\n")
            return code.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
        }
        return s
    }

    public var capJson: String {
        enum Delimiter: String {
            case object = "{"
            case array = "["
            case string = "\""
        }
        var delimiterStack = [Delimiter]()

        var prevChar: Character?
        for char in self {
            if delimiterStack.last == .string {
                if char == "\"", let prevChar, prevChar != "\\" {
                    _ = delimiterStack.popLast()
                }
            } else {
                switch char {
                case "{": delimiterStack.append(.object)
                case "[": delimiterStack.append(.array)
                case "\"": delimiterStack.append(.string)
                case "}", "]": _ = delimiterStack.popLast()
                default: ()
                }
            }
            prevChar = char
        }

        var cappedString = self
        if cappedString.hasSuffix(",") {
            cappedString = String(cappedString.dropLast(1))
        }
        for delim in delimiterStack.reversed() {
            switch delim {
            case .array: cappedString += "]"
            case .string: cappedString += "\""
            case .object: cappedString += "}"
            }
        }
        return cappedString
    }

    public var capJavascript: String {
        enum Delimiter: String {
            case paren = "("
            case object = "{"
            case array = "["
            case doubleQuoteString = "\""
            case singleQuoteString = "'"
            case tildeString = "`"
        }
        var delimiterStack = [Delimiter]()

        var prevChar: Character?
        for char in self {
            if delimiterStack.last == .doubleQuoteString {
                if char == "\"", let prevChar, prevChar != "\\" {
                    _ = delimiterStack.popLast()
                }
            } else if delimiterStack.last == .singleQuoteString {
                if char == "'", let prevChar, prevChar != "\\" {
                    _ = delimiterStack.popLast()
                }
            } else if delimiterStack.last == .tildeString {
                if char == "`", let prevChar, prevChar != "\\" {
                    _ = delimiterStack.popLast()
                }
            } else {
                switch char {
                case "(": delimiterStack.append(.paren)
                case "{": delimiterStack.append(.object)
                case "[": delimiterStack.append(.array)
                case "\"": delimiterStack.append(.doubleQuoteString)
                case "'": delimiterStack.append(.singleQuoteString)
                case "`": delimiterStack.append(.tildeString)
                case "}", "]", ")": _ = delimiterStack.popLast()
                default: ()
                }
            }
            prevChar = char
        }

        var cappedString = self
        if cappedString.hasSuffix(",") {
            cappedString = String(cappedString.dropLast(1))
        }
        for delim in delimiterStack.reversed() {
            switch delim {
            case .array: cappedString += "]"
            case .doubleQuoteString: cappedString += "\""
            case .singleQuoteString: cappedString += "'"
            case .tildeString: cappedString += "`"
            case .object: cappedString += "}"
            case .paren: cappedString += ")"
            }
        }
        return cappedString
    }
}
