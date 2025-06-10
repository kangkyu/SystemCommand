import SwiftUI

struct ContentView: View {
    @State private var showFileImporter = false
    @State private var importedFileURLs: [URL] = []
    @State private var exportMessage: String? = nil
    @State private var showFileExporter = false
    @State private var mergedVideoURL: URL? = nil
    @State private var isMerging = false
    @State private var mergingProgress: Double = 0.0
    @State private var currentStep: String = ""
    @State private var showFFmpegAlert = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Video File Manager")
                .font(.largeTitle)
                .fontWeight(.bold)

            Button("Import Videos") {
                if checkFFmpegInstallation() {
                    showFileImporter = true
                } else {
                    showFFmpegAlert = true
                }
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
                            ForEach(Array(importedFileURLs.enumerated()), id: \.offset) { index, url in
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
                                        importedFileURLs.remove(at: index)
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

                    Button(isMerging ? "Merging Videos..." : "Merge Videos") {
                        mergeVideos()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(isMerging || importedFileURLs.count < 2)

                    if isMerging {
                        VStack {
                            ProgressView(value: mergingProgress, total: 1.0)
                                .progressViewStyle(LinearProgressViewStyle())
                            Text(currentStep)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(Int(mergingProgress * 100))% complete")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 8)
                    }
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
            document: VideoDocument(url: mergedVideoURL),
            contentType: .mpeg4Movie,
            defaultFilename: "merged_video.mp4"
        ) { result in
            switch result {
            case .success(let url):
                exportMessage = "✅ Merged video saved to: \(url.path)"
                importedFileURLs.removeAll() // Clear the list after successful export
            case .failure(let error):
                exportMessage = "❌ Save failed: \(error.localizedDescription)"
            }
        }
        .alert("FFmpeg Not Found", isPresented: $showFFmpegAlert) {
            Button("OK") { }
        } message: {
            Text("FFmpeg is required to merge videos.\n\nTo install FFmpeg:\n1. Install Homebrew (https://brew.sh/) if not installed\n2. Install FFmpeg (brew install ffmpeg)\n3. Restart this app")
        }
    }

    private func getTotalDuration() -> Double {
        return getTotalDurationForURLs(importedFileURLs)
    }

    private func getTotalDurationForURLs(_ urls: [URL]) -> Double {
        var totalDuration: Double = 0

        for url in urls {
            let duration = getVideoDuration(for: url)
            totalDuration += duration
        }

        return totalDuration
    }

    private func updateProgress(from progressURL: URL, totalDuration: Double) {
        guard let progressData = try? String(contentsOf: progressURL, encoding: .utf8) else {
            return
        }

        // Parse FFmpeg progress output
        let lines = progressData.components(separatedBy: .newlines)
        var currentTime: Double = 0

        for line in lines {
            if line.hasPrefix("out_time_ms=") {
                let timeString = String(line.dropFirst("out_time_ms=".count))
                if let microseconds = Double(timeString) {
                    currentTime = microseconds / 1_000_000 // Convert to seconds
                    break
                }
            }
        }

        let progress = min(currentTime / totalDuration, 1.0)

        DispatchQueue.main.async {
            self.mergingProgress = max(progress, self.mergingProgress) // Ensure progress only goes forward
        }
    }

    private func getVideoDuration(for url: URL) -> Double {
        let ffprobePath = "/opt/homebrew/bin/ffprobe" // which ffprobe (given location by brew install ffmpeg)
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = [
            "-v", "quiet",
            "-show_entries", "format=duration",
            "-of", "csv=p=0",
            url.path
        ]
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let duration = Double(output) {
                return duration
            }
        } catch {
            print("Error getting duration for \(url.lastPathComponent): \(error)")
        }

        return 0 // Return 0 if unable to get duration
    }

    private func mergeVideos() {
        guard importedFileURLs.count >= 2 else { return }

        isMerging = true
        mergingProgress = 0.0
        exportMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let tempDirectory = FileManager.default.temporaryDirectory
            let outputURL = tempDirectory.appendingPathComponent("merged_video.mp4")
            let progressURL = tempDirectory.appendingPathComponent("ffmpeg_progress.txt")

            // Step 1: Normalize all videos with progress tracking
            DispatchQueue.main.async {
                self.currentStep = "Preparing normalization..."
            }

            let normalizedURLs = self.normalizeVideosWithProgress()
            guard !normalizedURLs.isEmpty else {
                DispatchQueue.main.async {
                    self.isMerging = false
                    self.mergingProgress = 0.0
                    self.currentStep = ""
                    self.exportMessage = "❌ Video normalization failed"
                }
                return
            }

            // Step 2: Merge normalized videos (takes final 20% of progress)
            DispatchQueue.main.async {
                self.currentStep = "Merging videos..."
                self.mergingProgress = 0.8 // Start merge at 80%
            }

            // Calculate total duration of normalized videos
            let totalDuration = self.getTotalDurationForURLs(normalizedURLs)

            // Create file list for FFmpeg concat
            let fileListURL = tempDirectory.appendingPathComponent("file_list.txt")
            let fileListContent = normalizedURLs.map { url in
                "file '\(url.path)'"
            }.joined(separator: "\n")

            do {
                try fileListContent.write(to: fileListURL, atomically: true, encoding: .utf8)

                let ffmpegPath = "/opt/homebrew/bin/ffmpeg" // which ffmpeg (given location by brew install)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: ffmpegPath)
                process.arguments = [
                    "-f", "concat",
                    "-safe", "0",
                    "-i", fileListURL.path,
                    "-c", "copy",  // Now we can safely use copy since videos are normalized
                    "-progress", progressURL.path,
                    "-y",
                    outputURL.path
                ]

                // Start progress monitoring for merge phase
                let progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                    self.updateMergeProgress(from: progressURL, totalDuration: totalDuration)
                }

                try process.run()
                process.waitUntilExit()

                progressTimer.invalidate()

                DispatchQueue.main.async {
                    self.isMerging = false
                    self.mergingProgress = 0.0
                    self.currentStep = ""
                    if process.terminationStatus == 0 {
                        self.mergedVideoURL = outputURL
                        self.showFileExporter = true
                    } else {
                        self.exportMessage = "❌ Video merge failed"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isMerging = false
                    self.mergingProgress = 0.0
                    self.currentStep = ""
                    self.exportMessage = "❌ Merge error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func normalizeVideosWithProgress() -> [URL] {
        let tempDirectory = FileManager.default.temporaryDirectory
        var normalizedURLs: [URL] = []
        let totalVideos = importedFileURLs.count

        // Get durations of all videos first
        let videoDurations = importedFileURLs.map { getVideoDuration(for: $0) }
        let totalDuration = videoDurations.reduce(0, +)
        var processedDuration: Double = 0

        for (index, url) in importedFileURLs.enumerated() {
            let outputURL = tempDirectory.appendingPathComponent("normalized_\(index).mp4")
            let progressURL = tempDirectory.appendingPathComponent("normalize_progress_\(index).txt")
            let videoDuration = videoDurations[index]
            let currentProcessedDuration = processedDuration // Capture current value

            DispatchQueue.main.async {
                self.currentStep = "Normalizing video \(index + 1) of \(totalVideos): \(url.lastPathComponent)"
            }

            let ffmpegPath = "/opt/homebrew/bin/ffmpeg"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpegPath)

            process.arguments = [
                "-i", url.path,
                "-vf", "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,fps=30",
                "-c:v", "libx264",
                "-preset", "fast",
                "-crf", "18",
                "-c:a", "aac",
                "-ar", "48000",
                "-ac", "2",
                "-b:a", "256k",
                "-progress", progressURL.path,
                "-y",
                outputURL.path
            ]

            // Start progress monitoring for this video
            let progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                self.updateNormalizationProgress(
                    from: progressURL,
                    videoDuration: videoDuration,
                    processedDuration: currentProcessedDuration, // Use captured value
                    totalDuration: totalDuration,
                    videoIndex: index + 1,
                    totalVideos: totalVideos
                )
            }

            do {
                try process.run()
                process.waitUntilExit()

                progressTimer.invalidate()

                if process.terminationStatus == 0 {
                    normalizedURLs.append(outputURL)
                    processedDuration += videoDuration // Update after timer is done

                    // Update progress after completing this video
                    DispatchQueue.main.async {
                        self.mergingProgress = min((processedDuration / totalDuration) * 0.8, 0.8)
                    }
                } else {
                    progressTimer.invalidate()
                    print("Failed to normalize video: \(url.lastPathComponent)")
                    return []
                }
            } catch {
                progressTimer.invalidate()
                print("Error normalizing video \(url.lastPathComponent): \(error)")
                return []
            }
        }

        return normalizedURLs
    }

    private func updateNormalizationProgress(from progressURL: URL, videoDuration: Double, processedDuration: Double, totalDuration: Double, videoIndex: Int, totalVideos: Int) {
        guard let progressData = try? String(contentsOf: progressURL, encoding: .utf8) else {
            return
        }

        let lines = progressData.components(separatedBy: .newlines)
        var currentTime: Double = 0

        for line in lines {
            if line.hasPrefix("out_time_ms=") {
                let timeString = String(line.dropFirst("out_time_ms=".count))
                if let microseconds = Double(timeString) {
                    currentTime = microseconds / 1_000_000
                    break
                }
            }
        }

        // Calculate overall progress: (completed videos + current video progress) / total
        let currentVideoProgress = min(currentTime / videoDuration, 1.0)
        let overallProgress = (processedDuration + (currentVideoProgress * videoDuration)) / totalDuration

        DispatchQueue.main.async {
            // Normalization takes 80% of total progress
            self.mergingProgress = min(overallProgress * 0.8, 0.8)

            // Update step text with current video progress
            let videoProgressPercent = Int(currentVideoProgress * 100)
            self.currentStep = "Normalizing video \(videoIndex) of \(totalVideos): \(videoProgressPercent)%"
        }
    }

    private func updateMergeProgress(from progressURL: URL, totalDuration: Double) {
        guard let progressData = try? String(contentsOf: progressURL, encoding: .utf8) else {
            return
        }

        let lines = progressData.components(separatedBy: .newlines)
        var currentTime: Double = 0

        for line in lines {
            if line.hasPrefix("out_time_ms=") {
                let timeString = String(line.dropFirst("out_time_ms=".count))
                if let microseconds = Double(timeString) {
                    currentTime = microseconds / 1_000_000
                    break
                }
            }
        }

        // Merge progress takes the final 20% (0.8 to 1.0)
        let mergeProgress = min(currentTime / totalDuration, 1.0)
        let totalProgress = 0.8 + (mergeProgress * 0.2)

        DispatchQueue.main.async {
            self.mergingProgress = max(totalProgress, self.mergingProgress)
        }
    }

    private func normalizeVideos() -> [URL] {
        let tempDirectory = FileManager.default.temporaryDirectory
        var normalizedURLs: [URL] = []

        for (index, url) in importedFileURLs.enumerated() {
            let outputURL = tempDirectory.appendingPathComponent("normalized_\(index).mp4")

            let ffmpegPath = "/opt/homebrew/bin/ffmpeg" // which ffmpeg (given location by brew install)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpegPath)

            // Normalize to consistent format: Keep original resolution, 30fps, H.264, AAC
            process.arguments = [
                "-i", url.path,
                "-vf", "fps=30",        // Only normalize frame rate
                "-c:v", "libx264",      // H.264 codec
                "-preset", "fast",    // Encoding speed vs quality (eg. "medium", "slow")
                "-crf", "18",           // Quality (lower = better quality, eg. "23")
                "-c:a", "aac",          // AAC audio codec
                "-ar", "48000",         // Audio rate (how many samples per second), 48 khz: standard for video
                "-ac", "2",             // Stereo audio
                "-b:a", "256k",         // Audio bitrate (how much data per second), 256-320 kbps: Very high quality
                "-y",
                outputURL.path
            ]

            do {
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    normalizedURLs.append(outputURL)
                } else {
                    print("Failed to normalize video: \(url.lastPathComponent)")
                    return [] // Return empty array on failure
                }
            } catch {
                print("Error normalizing video \(url.lastPathComponent): \(error)")
                return []
            }
        }

        return normalizedURLs
    }

    private func checkFFmpegInstallation() -> Bool {
        let ffmpegPath = "/opt/homebrew/bin/ffmpeg"
        let ffprobePath = "/opt/homebrew/bin/ffprobe"

        return FileManager.default.fileExists(atPath: ffmpegPath) &&
               FileManager.default.fileExists(atPath: ffprobePath)
    }
}
