import Foundation

public enum AudioDataFormat: String {
    case mp3
    case wav
}

public struct Transcription: Equatable, Codable {
    public var text: String

    init(text: String) {
        self.text = text
    }
}

public protocol RecordedSpeechRecognizer {
    func transcribe(audioData: Data, format: AudioDataFormat) async throws -> Transcription
}

// TODO: Add ContinuousSpeechRecognizer
