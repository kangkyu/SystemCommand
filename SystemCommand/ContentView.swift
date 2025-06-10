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
    @State private var exportMessage: String? = nil

    var body: some View {
        VStack(spacing: 20) {
            Text("Video File Manager")
                .font(.largeTitle)
                .fontWeight(.bold)

            Button("Import Videos") {
                showFileImporter = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if !importedFileURLs.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Imported Videos (\(importedFileURLs.count))")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(importedFileURLs, id: \.self) { url in
                                HStack {
                                    Image(systemName: "play.rectangle.fill")
                                        .foregroundColor(.blue)

                                    VStack(alignment: .leading) {
                                        Text(url.lastPathComponent)
                                            .font(.body)
                                            .lineLimit(1)
                                        Text(url.pathExtension.uppercased())
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Button("Remove") {
                                        importedFileURLs.removeAll { $0 == url }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .foregroundColor(.red)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .frame(maxHeight: 300)

                    Button("Export Video List") {
                        showFileExporter = true
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
            }

            if let exportMessage = exportMessage {
                Text(exportMessage)
                    .foregroundColor(.green)
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .padding()
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: true,
            onCompletion: { result in
                switch result {
                case .success(let urls):
                    importedFileURLs.append(contentsOf: urls)
                case .failure(let error):
                    print("Import error: \(error)")
                }
            }
        )
        .fileExporter(
            isPresented: $showFileExporter,
            document: TextDocument(content: createFileList()),
            contentType: .plainText,
            defaultFilename: "imported_files.txt",
            onCompletion: { result in
                switch result {
                case .success(let url):
                    exportMessage = "✅ Exported successfully to: \(url.path)"
                    importedFileURLs.removeAll()
                case .failure(let error):
                    exportMessage = "❌ Export failed: \(error.localizedDescription)"
                }
            }
        )
    }

    private func createFileList() -> String {
        return importedFileURLs.map { $0.lastPathComponent }.joined(separator: "\n")
    }
}
