import Foundation

public protocol SpeechGenerator {
    func speak(_ text: String) async // Adds to queue; does not wait until playback finishes
    func stop() async
    func awaitFinishedSpeaking() async
    func setManagesAudioSession(_ manages: Bool) async
    // Callback that's called when the generator has finished buffering and is ready to start speaking
    func setOnReadyToSpeak(_ block: (() -> Void)?) async
}
