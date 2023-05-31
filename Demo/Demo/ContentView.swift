import SwiftUI
import ChatToys

enum Screen: CaseIterable, Identifiable, Hashable {
    case chat
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
