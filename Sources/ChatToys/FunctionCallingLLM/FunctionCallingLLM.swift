import Foundation

public protocol FunctionCallingLLM {
    // TODO: Support streaming?
    func complete(prompt: [LLMMessage]) async throws -> LLMMessage
    var tokenLimit: Int { get } // aka context size
}

//public struct Function {
//    public var name: String
//    public var description: String
//    public var parameter: FunctionType
//
//    public struct Param {
//        public var description: String?
//    }
//}

public struct LLMFunction: Equatable, Codable {
    public var name: String
    public var description: String
    public var parameters: JsonSchema

    public init(name: String, description: String, parameters: JsonSchema) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    public struct JsonSchema: Equatable, Codable {
        public enum Data: String, Codable, Equatable {
            case string
            case object
            case number
            case integer
            case array
            case boolean
        }
        public var type: TypeField
        public var description: String?
        public var required: [String]? // for type=object
        public var properties: [String: JsonSchema]?
        public var items: JsonSchema? // for type=array
        public var `enum`: [String]? // For type=string that can take certain values

        public init(enumeratedValue: [String], description: String?) {
            self.type = .string
            self.enum = enumeratedValue
        }

        public init(objectWithProperties props: [String: JsonSchema], required: [String]?, description: String?) {
            self.type = .object
            self.properties = props
            self.required = required
            self.description = description
        }

        public init(arrayOfItems items: JsonSchema, description: String?) {
            self.type = .array
            self.items = items
            self.description = description
        }

        public init(integerWithDescription: String?) {
            self.type = .integer
            self.description = integerWithDescription
        }

        public init(numberWithDescription: String?) {
            self.type = .number
            self.description = numberWithDescription
        }

        public init(booleanWithDescription: String?) {
            self.type = .boolean
            self.description = booleanWithDescription
        }

        public init(stringWithDescription: String?) {
            self.type = .string
            self.description = stringWithDescription
        }
    }
}

public extension FunctionCallingLLM {
    // We can't currently run the real tokenizer on device, so token counts are estimates. You should leave a little 'wiggle room'
    var tokenLimitWithWiggleRoom: Int {
        max(1, Int(round(Double(tokenLimit) * 0.85)) - 50)
    }
}
