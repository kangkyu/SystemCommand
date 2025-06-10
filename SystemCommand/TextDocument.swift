//
//  Untitled.swift
//  SystemCommand
//
//  Created by Kang-Kyu Lee on 6/9/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct TextDocument: FileDocument {
    var content: String

    static var readableContentTypes: [UTType] { [.plainText] }

    init(content: String) {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        content = ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: content.data(using: .utf8) ?? Data())
    }
}
