import Foundation

public struct OpenAISpeechRecognizer: RecordedSpeechRecognizer {
    public var credentials: OpenAICredentials

    public init(credentials: OpenAICredentials) {
        self.credentials = credentials
    }

    public func transcribe(audioData: Data, format: AudioDataFormat) async throws -> Transcription {
        struct TranscriptionResponse: Codable {
            let text: String
        }
        
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
        if let orgId = credentials.orgId?.nilIfEmpty {
            request.setValue(orgId, forHTTPHeaderField: "OpenAI-Organization")
        }
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        // Add file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.\(format.rawValue)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/\(format.rawValue)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
                let dataString = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw OpenAISpeechRecognizerError.transcriptionFailed(dataString)
        }

        let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return Transcription(text: transcriptionResponse.text)
    }
}

enum OpenAISpeechRecognizerError: Error {
    case transcriptionFailed(String)
}
