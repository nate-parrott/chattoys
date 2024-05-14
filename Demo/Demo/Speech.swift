import Foundation
import ChatToys
import SwiftUI

//public protocol SpeechGenerator {
//    func speak(_ text: String) async // Adds to queue; does not wait until playback finishes
//    func stop() async
//    func awaitFinishedSpeaking() async
//}

enum TTSModel: String, CaseIterable {
    case apple = "apple"
    case openai = "openai"
    case eleven = "eleven"

    var model: any SpeechGenerator {
        switch self {
        case .apple:
            return AppleSpeechGenerator()
        case .eleven:
            return ElevenLabsSpeechGenerator(apiKey: UserDefaults.standard.string(forKey: "elevenLabsKey") ?? "")
        case .openai:
            let key = UserDefaults.standard.string(forKey: "key") ?? ""
            let orgId = UserDefaults.standard.string(forKey: "orgId") ?? ""
            return OpenAISpeechGenerator(credentials: .init(apiKey: key, orgId: orgId))
        }
    }
}

class Player: ObservableObject {
    init() {}

    var lastGenerator: (any SpeechGenerator)?

    func speak(_ text: String, model: TTSModel) async {
        lastGenerator = model.model
        await lastGenerator!.speak(text)
    }
}

struct TextToSpeechDemo: View {
    // Default to long poem
    @State var text: String = """
    The Road Not Taken
    By Robert Frost

    Two roads diverged in a yellow wood,
    And sorry I could not travel both
    And be one traveler, long I stood
    And looked down one as far as I could
    """
    @AppStorage("ttsModel") var model: TTSModel = .apple
    @StateObject var player = Player()

    var body: some View {
        Form {
            Section {
                Picker("Model", selection: $model) {
                    Text("Apple").tag(TTSModel.apple)
                    Text("Eleven").tag(TTSModel.eleven)
                    Text("OpenAI").tag(TTSModel.openai)
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            Section {
                TextEditor(text: $text)
            }
            Section {
                Button("Speak") {
                    Task {
                        await player.speak(text, model: model)
                    }
                }
            }
        }
    }
}
