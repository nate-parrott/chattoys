import Foundation
import AVFoundation

// 2ovNLFOsfyKPEWV5kqQi

/*
 {
   "text": "<string>",
   "model_id": "<string>",
   "voice_settings": {
     "stability": 123,
     "similarity_boost": 123,
     "style": 123,
     "use_speaker_boost": true
   },
   "pronunciation_dictionary_locators": [
     {
       "pronunciation_dictionary_id": "<string>",
       "version_id": "<string>"
     }
   ],
   "seed": 123,
   "previous_text": "<string>",
   "next_text": "<string>",
   "previous_request_ids": [
     "<string>"
   ],
   "next_request_ids": [
     "<string>"
   ]
 */

public actor ElevenLabsSpeechGenerator: SpeechGenerator {
    public struct Options {
        public var voiceId: String

        public init(voiceId: String = "3L3MjomRjzkkVi1ib9PX") {
            self.voiceId = voiceId
        }
    }

    private let apiKey: String

    public var options: Options
    let queuePlayer = AVQueuePlayer()

    public init(apiKey: String, options: Options = .init()) {
        self.apiKey = apiKey
        self.options = options
    }

    public func update(options: Options) {
        self.options = options
    }

    public var managesAudioSession = true
    public func setManagesAudioSession(_ manages: Bool) async {
        managesAudioSession = manages
    }

    public func setOnReadyToSpeak(_ block: (() -> Void)?) {
        self.onReadyToSpeak = block
    }
    public var onReadyToSpeak: (() -> Void)?

    //  MARK: - SpeechGenerator

    public func speak(_ text: String) async { // Adds to queue; does not wait until playback finishes
        // TODO: Enforce queue
        self.speaking = true
        let task = Task {
            await _fetchAndPlay(text: text)
//            for sentence in text.splitIntoSentences {
//                await _fetchAndPlay(text: sentence)
//                try? await Task.sleep(seconds: 0.3)
//            }
        }
        tasks.append(task)
    }

    public func stop() async {
        for task in tasks {
            task.cancel()
        }
        queuePlayer.removeAllItems()
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

    // MARK: - Playback
    private func _fetchAndPlay(text: String) async {
        enum Errors: Error {
            case invalidVoiceIdFormat
        }
        do {
            // Construct request and download MP3 to data

            guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(options.voiceId)/stream") else {
                throw Errors.invalidVoiceIdFormat
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            struct Request: Codable {
                var text: String
                var optimize_streaming_latency: Int
                var output_format: String = "mp3_44100_32"
                var model_id: String = "eleven_turbo_v2"
            }
            let requestObject = Request(text: text, optimize_streaming_latency: 4)
            request.httpBody = try JSONEncoder().encode(requestObject)

            let data = try await URLSession.shared.data(for: request).0
            do {
                try Task.checkCancellation()
            } catch {
                return
            }

            let tempURL = data.writeToTemporaryDirectory(withExtension: "mp3")
            let playerItem = AVPlayerItem(url: tempURL)
            queuePlayer.insert(playerItem, after: nil)
            print("Will play \(text)")
            NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: playerItem, queue: .main) { [weak self] item in
                Task {
                    await self?._finishedPlayingItem(item.object as! AVPlayerItem)
                }
            }
            self.onReadyToSpeak?()
            await queuePlayer.play()

        }
         catch {
            print("[VoiceQueue] Failed to play audio with error \(error)")
            finishedSpeaking()
         }
    }

    // MARK: - Audio session

    private var speaking = false {
        didSet {
            if speaking != oldValue, managesAudioSession {
                do {
                    #if os(iOS)
                    if speaking {
                        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                        try AVAudioSession.sharedInstance().setActive(true)
                    } else {
                        try AVAudioSession.sharedInstance().setActive(false)
                    }
                    #endif
                } catch {
                    print("[VoiceQueue] Failed to update audio session with error \(error)")
                }
            }
        }
    }

    // MARK: - Finish tracking
    var onFinishBlocks = [() -> Void]()
    var tasks = [Task<Void, Never>]()

    private func finishedSpeaking() {
        speaking = false

        let blocks = onFinishBlocks
        onFinishBlocks = []
        for block in blocks {
            block()
        }
    }

    private func _finishedPlayingItem(_ item: AVPlayerItem) {
        if queuePlayer.items().last == item || queuePlayer.items().count == 0 {
            finishedSpeaking()
        }
    }
}

