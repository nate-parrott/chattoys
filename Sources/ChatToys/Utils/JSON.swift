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
