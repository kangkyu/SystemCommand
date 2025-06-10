import SwiftUI
import AVFoundation

struct ContentView: View {
    @State private var showFileImporter = false
    @State private var importedFileURLs: [URL] = []
    @State private var exportMessage: String? = nil
    @State private var showFileExporter = false
    @State private var mergedVideoURL: URL? = nil
    @State private var isMerging = false
    @State private var mergingProgress: Double = 0.0
    @State private var currentStep: String = ""

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
                        mergeVideosWithAVFoundation()
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
    }

    private func mergeVideosWithAVFoundation() {
        guard importedFileURLs.count >= 2 else { return }

        isMerging = true
        mergingProgress = 0.0
        exportMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.main.async {
                self.currentStep = "Creating composition..."
                self.mergingProgress = 0.1
            }

            // Create the composition
            let composition = AVMutableComposition()

            guard let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ),
            let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                DispatchQueue.main.async {
                    self.isMerging = false
                    self.mergingProgress = 0.0
                    self.currentStep = ""
                    self.exportMessage = "❌ Failed to create composition tracks"
                }
                return
            }

            var currentTime = CMTime.zero
            let totalVideos = self.importedFileURLs.count

            // Add each video to the composition
            for (index, videoURL) in self.importedFileURLs.enumerated() {
                DispatchQueue.main.async {
                    self.currentStep = "Adding video \(index + 1) of \(totalVideos)"
                    self.mergingProgress = 0.1 + (Double(index) / Double(totalVideos)) * 0.7 // 10% to 80%
                }

                // Start accessing security-scoped resource
                let accessed = videoURL.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        videoURL.stopAccessingSecurityScopedResource()
                    }
                }

                let asset = AVAsset(url: videoURL)

                // Get video track
                guard let assetVideoTrack = asset.tracks(withMediaType: .video).first else {
                    DispatchQueue.main.async {
                        self.isMerging = false
                        self.mergingProgress = 0.0
                        self.currentStep = ""
                        self.exportMessage = "❌ No video track found in \(videoURL.lastPathComponent)"
                    }
                    return
                }

                do {
                    // Insert video track
                    try videoTrack.insertTimeRange(
                        CMTimeRange(start: .zero, duration: asset.duration),
                        of: assetVideoTrack,
                        at: currentTime
                    )

                    // Insert audio track (if exists)
                    if let assetAudioTrack = asset.tracks(withMediaType: .audio).first {
                        try audioTrack.insertTimeRange(
                            CMTimeRange(start: .zero, duration: asset.duration),
                            of: assetAudioTrack,
                            at: currentTime
                        )
                    }

                    currentTime = CMTimeAdd(currentTime, asset.duration)

                } catch {
                    DispatchQueue.main.async {
                        self.isMerging = false
                        self.mergingProgress = 0.0
                        self.currentStep = ""
                        self.exportMessage = "❌ Failed to add \(videoURL.lastPathComponent): \(error.localizedDescription)"
                    }
                    return
                }
            }

            DispatchQueue.main.async {
                self.currentStep = "Preparing export..."
                self.mergingProgress = 0.8
            }

            // Create output URL
            let tempDirectory = FileManager.default.temporaryDirectory
            let outputURL = tempDirectory.appendingPathComponent("merged_video.mp4")

            // Remove existing file if it exists
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }

            // Create export session
            guard let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality
            ) else {
                DispatchQueue.main.async {
                    self.isMerging = false
                    self.mergingProgress = 0.0
                    self.currentStep = ""
                    self.exportMessage = "❌ Failed to create export session"
                }
                return
            }

            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4

            // Monitor export progress
            let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                DispatchQueue.main.async {
                    let exportProgress = exportSession.progress
                    self.mergingProgress = 0.8 + (Double(exportProgress) * 0.2) // 80% to 100%
                    self.currentStep = "Exporting: \(Int(exportProgress * 100))%"
                }
            }

            // Start export
            exportSession.exportAsynchronously {
                progressTimer.invalidate()

                DispatchQueue.main.async {
                    self.isMerging = false
                    self.mergingProgress = 0.0
                    self.currentStep = ""

                    switch exportSession.status {
                    case .completed:
                        self.mergedVideoURL = outputURL
                        self.showFileExporter = true
                    case .failed:
                        let errorMessage = exportSession.error?.localizedDescription ?? "Unknown error"
                        self.exportMessage = "❌ Export failed: \(errorMessage)"
                    case .cancelled:
                        self.exportMessage = "❌ Export was cancelled"
                    default:
                        self.exportMessage = "❌ Export failed with unknown status"
                    }
                }
            }
        }
    }

    private func getVideoDurationAV(for url: URL) -> Double {
        let asset = AVAsset(url: url)
        return CMTimeGetSeconds(asset.duration)
    }

    private func getTotalDuration() -> Double {
        return getTotalDurationForURLs(importedFileURLs)
    }

    private func getTotalDurationForURLs(_ urls: [URL]) -> Double {
        var totalDuration: Double = 0

        for url in urls {
            let duration = getVideoDurationAV(for: url)
            totalDuration += duration
        }

        return totalDuration
    }
}
