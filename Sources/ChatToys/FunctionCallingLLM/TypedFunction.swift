import Foundation

/*
 This is a typed wrapper around LLMFunction. Usage:

 //  Define your function arguments as a struct:
 struct EditFileFunctionArgs: FunctionArgs {
     var path: String
     var content: String

     static var schema: [String: LLMFunction.JsonSchema] {
         [
             "path": .string(description: "The path to edit"),
             "content": .string(description: "The text that will be written to this file path, overwriting any existing content")
         ]
     }
 }

 // Create your typed function:
 let editFileFunction = TypedFunction(name: "edit_file", description: "Edits a file on disk", type: EditFileFunctionArgs.self)

 // Create a plain LLMFunction when doing your function call:
 // let response = try await llm.complete(prompt: ..., functions: [editFileFunction.asLLMFunction])

 // If you encounter a function call, check to see if it matches your typed function
 if let args = editFileFunction.checkMatch(call: message.functionCalls[0], streaming: false) {
     // Handle the function call using the typed `args` object
     print("Path: \(args.path)")
 }

 */

public struct TypedFunction<T: FunctionArgs> {
    public var name: String
    public var description: String
    public var type: T.Type

    public init(name: String, description: String, type: T.Type) {
        self.name = name
        self.description = description
        self.type = type
    }

    public var asLLMFunction: LLMFunction {
        LLMFunction(name: name, description: description, parameters: T.schema)
    }

    public func checkMatch(call: LLMMessage.FunctionCall, streaming: Bool = false) -> T? {
        if call.name == self.name, let decodedArgs = call.decodeArguments(as: type, stream: streaming) {
            return decodedArgs
        }
        return nil
    }
}

public protocol FunctionArgs: Codable {
    // The schema should describe the function to the LLM
    static var schema: [String: LLMFunction.JsonSchema] { get }
}
