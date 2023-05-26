import Foundation

public struct OpenAICredentials {
    var apiKey: String
    var orgId: String?

    public init(apiKey: String, orgId: String? = nil) {
        self.apiKey = apiKey
        self.orgId = orgId
    }
}

//enum OpenAIError: Error {
//    case noChoices
//    case invalidResponse(String)
//    case noApiKey
//}
