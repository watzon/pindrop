//
//  ContentView.swift
//  Pindrop
//
//  Created on 1/25/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "mic.fill")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Pindrop")
                .font(.title)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
