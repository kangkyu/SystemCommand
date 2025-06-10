//
//  Scripting.swift
//  SystemCommand
//
//  Created by Kang-Kyu Lee on 6/9/25.
//

import Foundation

@discardableResult
func shell(_ command: String) -> String {
    let task = Process()
    let pipe = Pipe()

    task.standardOutput = pipe
    task.standardError = pipe

    task.arguments = ["-c", command]
    task.launchPath = "/bin/bash"

    task.standardInput = nil
    task.launch()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)!

    return output
}
