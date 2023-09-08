import SwiftUI
import ChatToys

enum Screen: CaseIterable, Identifiable, Hashable {
    case chat
    case search
    case scraping
    case semanticSearch
    case settings

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

            SemanticSearchDemo()
                .tabItem {
                    Label("SemanticSearch", systemImage: "lasso.and.sparkles")
                }
                .tag(Screen.semanticSearch)

            Scraper()
                .tabItem {
                    Label("Scraping", systemImage: "text.magnifyingglass")
                }
                .tag(Screen.scraping)
                
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
