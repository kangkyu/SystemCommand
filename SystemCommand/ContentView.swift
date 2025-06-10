//
//  ContentView.swift
//  SystemCommand
//
//  Created by Kang-Kyu Lee on 6/9/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {

            Button("Run commands") {
                print(shell("/opt/homebrew/bin/ffmpeg -version"))
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
