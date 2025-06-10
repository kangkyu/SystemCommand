//
//  VideoDocument.swift
//  SystemCommand
//
//  Created by Kang-Kyu Lee on 6/9/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct VideoDocument: FileDocument {
    var url: URL?

    static var readableContentTypes: [UTType] { [.mpeg4Movie] }

    init(url: URL?) {
        self.url = url
    }

    init(configuration: ReadConfiguration) throws {
        url = nil
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let url = url else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return try FileWrapper(url: url)
    }
}
