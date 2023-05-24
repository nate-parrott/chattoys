//
//  ContentView.swift
//  Demo
//
//  Created by nate parrott on 5/24/23.
//

import SwiftUI
import ChatToys

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundColor(.accentColor)
            Text("Text: \(ChatToys().text)!")
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
