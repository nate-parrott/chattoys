import Foundation

public protocol FunctionCallingLLM {
    func complete(prompt: [LLMMessage], functions: [LLMFunction]) async throws -> LLMMessage
    func completeStreaming(prompt: [LLMMessage], functions: [LLMFunction]) -> AsyncThrowingStream<LLMMessage, Error>
    var tokenLimit: Int { get } // aka context size
}

public struct LLMFunction: Equatable, Encodable {
    public var name: String
    public var description: String
    public var parameters: JsonSchema
    public var strict: Bool?

    public init(name: String, description: String, parameters: [String: JsonSchema], required: [String]? = nil, strict: Bool? = nil) {
        self.name = name
        self.description = description
        self.parameters = .object(description: nil, properties: parameters, required: required ?? Array(parameters.keys))
        self.strict = strict
    }

    public indirect enum JsonSchema: Equatable, Encodable {
        case string(description: String?) // Encode as type=string, description=description
        case number(description: String?) // Encode as type=number, description=description
        case boolean(description: String?) // Encode as type=boolean, description=description
        case enumerated(description: String?, options: [String]) // Encode as type=string, enum=options, description=description
        case object(description: String?, properties: [String: JsonSchema], required: [String]) // Encode as type=object, properties=properties, required=required
        case array(description: String?, itemType: JsonSchema) // Encode as type=array, items=itemType

        public func encode(to encoder: Encoder) throws {
            // Do not include nil keys
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .string(let description):
                try container.encode("string", forKey: .type)
                if let description = description {
                    try container.encode(description, forKey: .description)
                }
            case .number(let description):
                try container.encode("number", forKey: .type)
                if let description = description {
                    try container.encode(description, forKey: .description)
                }
            case .boolean(let description):
                try container.encode("boolean", forKey: .type)
                if let description = description {
                    try container.encode(description, forKey: .description)
                }
            case .enumerated(let description, let options):
                try container.encode("string", forKey: .type)
                try container.encode(options, forKey: .enum)
                if let description = description {
                    try container.encode(description, forKey: .description)
                }
            case .object(let description, let properties, let required):
                try container.encode("object", forKey: .type)
                try container.encode(properties, forKey: .properties)
                try container.encode(required, forKey: .required)
                if let description = description {
                    try container.encode(description, forKey: .description)
                }
            case .array(let description, let itemType):
                try container.encode("array", forKey: .type)
                try container.encode(itemType, forKey: .items)
                if let description = description {
                    try container.encode(description, forKey: .description)
                }
            }
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case description
            case `enum`
            case properties
            case required
            case items
        }
    }
}

public extension FunctionCallingLLM {
    // We can't currently run the real tokenizer on device, so token counts are estimates. You should leave a little 'wiggle room'
    var tokenLimitWithWiggleRoom: Int {
        max(1, Int(round(Double(tokenLimit) * 0.85)) - 50)
    }
}
