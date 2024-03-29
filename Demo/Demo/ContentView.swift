import SwiftUI
import ChatToys

enum Screen: CaseIterable, Identifiable, Hashable {
    case chat
    case search
    case scraping
    case semanticSearch
    case functionCalling
    case textToSpeech
    case settings
    case markdown
    case automation

    var id: Self { self }
}

struct ContentView: View {
    @State private var screen: Screen = .settings
    var body: some View {
        TabView(selection: $screen) {
            ChatDemo()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(Screen.chat)

            SearchDemo()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(Screen.search)

            HTMLToMarkdownDemo()
                .tabItem {
                    Label("Markdown", systemImage: "ellipsis.curlybraces")
                }
                .tag(Screen.markdown)

            AutomationDemo()
                .tabItem {
                    Label("Automation", systemImage: "ellipsis.curlybraces")
                }
                .tag(Screen.automation)

            SemanticSearchDemo()
                .tabItem {
                    Label("SemanticSearch", systemImage: "lasso.and.sparkles")
                }
                .tag(Screen.semanticSearch)

            FunctionCallingDemo()
                .tabItem {
                    Label("Functions", systemImage: "wifi")
                }
                .tag(Screen.functionCalling)


            Scraper()
                .tabItem {
                    Label("Scraping", systemImage: "text.magnifyingglass")
                }
                .tag(Screen.scraping)

            TextToSpeechDemo()
                .tabItem {
                    Label("TTS", systemImage: "speaker.wave.2")
                }
                .tag(Screen.textToSpeech)
                
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(Screen.settings)
        }
        .padding()
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
