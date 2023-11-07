import AVFoundation

public actor AppleSpeechGenerator: NSObject, SpeechGenerator {
    private lazy var synthesizer: AVSpeechSynthesizer = {
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = false
        return synthesizer
    }()

    public override init() {
        super.init()
    }

    // MARK: - API

    public func speak(_ text: String) {
        #if targetEnvironment(simulator)
        return
        #endif
        synthesizer.delegate = self
        speaking = true

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.57
        utterance.postUtteranceDelay = 0.2
        if let voice = AVSpeechSynthesisVoice(identifier: AVSpeechSynthesisVoiceIdentifierAlex) {
            utterance.voice = voice
        }
        lastUtterance = utterance

//        // Retrieve the British English voice.
//        let voice = AVSpeechSynthesisVoice(language: "en-US")!
//        // Assign the voice to the utterance.
//        utterance.voice = voice

        synthesizer.speak(utterance)
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        finishedSpeaking()
    }

    public func awaitFinishedSpeaking() async {
        if !speaking { return }
        await withCheckedContinuation { cont in
            onFinishBlocks.append {
                cont.resume()
            }
        }
    }

    // MARK: - Audio session

    private var speaking = false {
        didSet {
            if speaking != oldValue {
                do {
                    if speaking {
                        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                        try AVAudioSession.sharedInstance().setActive(true)
                    } else {
                        try AVAudioSession.sharedInstance().setActive(false)
                    }
                } catch {
                    print("[VoiceQueue] Failed to update audio session with error \(error)")
                }
            }
        }
    }

    // MARK: - Finish tracking
    var lastUtterance: AVSpeechUtterance?
    var onFinishBlocks = [() -> Void]()

    private func finishedSpeaking() {
        speaking = false

        let blocks = onFinishBlocks
        onFinishBlocks = []
        for block in blocks {
            block()
        }
    }
}

extension AppleSpeechGenerator: AVSpeechSynthesizerDelegate {
    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task {
            await didFinish(utterance: utterance)
        }
    }

    private func didFinish(utterance: AVSpeechUtterance) {
        if utterance == lastUtterance {
            lastUtterance = nil
            finishedSpeaking()
        }
    }
}
