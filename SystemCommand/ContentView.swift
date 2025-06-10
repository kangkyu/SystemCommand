//
//  ContentView.swift
//  SystemCommand
//
//  Created by Kang-Kyu Lee on 6/9/25.
//

import SwiftUI

struct ContentView: View {
    @State private var showFileImporter = false
    @State private var showFileExporter = false
    @State private var importedFileURLs: [URL] = []

    var body: some View {
        VStack {
            Button("Import File") {
                showFileImporter = true
            }

            if !importedFileURLs.isEmpty {
                Text("Imported \(importedFileURLs.count) files")

                VStack {
                    ForEach(importedFileURLs, id: \.self) { url in
                        HStack {
                            Text(url.lastPathComponent)
                            Spacer()
                            Button("Remove") {
                                importedFileURLs.removeAll { $0 == url }
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(.red)
                        }
                    }
                }

                Button("Export File List") {
                    showFileExporter = true
                }
            }
        }
        .padding()
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.movie], allowsMultipleSelection: true, onCompletion: { result in
            switch result {
            case .success(let urls):
                importedFileURLs.append(contentsOf: urls)
            case .failure(let error):
                print("Import error: \(error)")
            }
        })
        .fileExporter(isPresented: $showFileExporter, document: TextDocument(content: createFileList()), contentType: .plainText, defaultFilename: "imported_files.txt", onCompletion: { result in
            switch result {
            case .success(let url):
                print("Exported to: \(url)")
            case .failure(let error):
                print("Export error: \(error)")
            }
        })
    }

    private func createFileList() -> String {
        return importedFileURLs.map { $0.lastPathComponent }.joined(separator: "\n")
    }
}
