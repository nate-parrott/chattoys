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
        for separator in ["```", "`"] {
            let parts = self.components(separatedBy: separator)
            if parts.count == 1 {
                continue
            }
            let code = parts.enumerated().filter { $0.offset % 2 == 1 }.map { $0.element }.joined(separator: "\n")
            return code.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
        }
        return self
    }

    var capJson: String {
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
}
