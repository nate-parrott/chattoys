import Foundation
import AVFoundation

public actor OpenAISpeechGenerator: SpeechGenerator {
    public struct Options {
        public var voice: Voice = .alloy
        public var speed: Double = 1.0 /* 0.25 to 4 */

        public init(voice: Voice = .alloy, speed: Double = 1.0) {
            self.voice = voice
            self.speed = speed
        }
    }

    public enum Voice: String, Equatable, CaseIterable {
        case alloy
        case echo
        case fable
        case onyx
        case nova
        case shimmer
    }

    private let credentials: OpenAICredentials

    public var options: Options
    let queuePlayer = AVQueuePlayer()

    public init(credentials: OpenAICredentials, options: Options = .init()) {
        self.credentials = credentials
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
        let task = Task {
            await _fetchAndPlay(text: text)
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
        speaking = true
        do {
            // Construct request and download MP3 to data

            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let orgId = credentials.orgId?.nilIfEmpty {
                request.setValue(orgId, forHTTPHeaderField: "OpenAI-Organization")
            }
            struct Request: Codable {
                var model: String = "tts-1"
                var input: String
                var voice: String = "alloy"
                var response_format: String = "mp3"
                var speed: Double
            }
            let requestObject = Request(input: text, voice: options.voice.rawValue, speed: options.speed)
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
            
            NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: playerItem, queue: .main) { [weak self] item in
                Task {
                    await self?._finishedPlayingItem(item.object as! AVPlayerItem)
                }
            }

            onReadyToSpeak?()
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

    private func _finishedPlayingItem(_ item: AVPlayerItem) {
        if queuePlayer.items().last == item || queuePlayer.items().count == 0 {
            finishedSpeaking()
        }
    }

    private func finishedSpeaking() {
        speaking = false

        let blocks = onFinishBlocks
        onFinishBlocks = []
        for block in blocks {
            block()
        }
    }
}

extension Data {
    func writeToTemporaryDirectory(withExtension ext: String) -> URL {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        try! write(to: tempFile)
        return tempFile
    }
}
