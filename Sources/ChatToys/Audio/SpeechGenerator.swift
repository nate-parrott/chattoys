import Foundation

public protocol SpeechGenerator {
    func speak(_ text: String) async // Adds to queue; does not wait until playback finishes
    func stop() async
    func awaitFinishedSpeaking() async
}
