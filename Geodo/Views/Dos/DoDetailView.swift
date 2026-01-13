import SwiftUI
import SwiftData
import AVKit

// Wrapper view for safe video playback
struct VideoPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = AVPlayer(url: url)
        playerView.controlsStyle = .inline
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // No updates needed
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player?.pause()
        nsView.player = nil
    }
}

struct DoDetailView: View {
    @Bindable var doItem: Do
    @Environment(\.modelContext) private var modelContext
    @State private var isGeneratingDescription = false

    private var videoURL: URL? {
        guard let urlString = doItem.videoFileURL else { return nil }
        // Handle both file:// URLs and raw paths
        if urlString.hasPrefix("file://") {
            return URL(string: urlString)
        } else {
            return URL(fileURLWithPath: urlString)
        }
    }

    private var hasVideoFile: Bool {
        guard let url = videoURL else { return false }
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        // Check file has content (not 0 bytes)
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes?[.size] as? Int64 ?? 0
        return fileSize > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Video player - primary focus
            if hasVideoFile, let url = videoURL {
                VideoPlayerView(url: url)
                    .frame(minHeight: 300, maxHeight: 400)
            } else {
                // No video placeholder
                ZStack {
                    Color.black.opacity(0.8)
                    VStack(spacing: 12) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.cream.opacity(0.5))
                        Text("Video not available")
                            .font(.system(size: 14))
                            .foregroundColor(.cream.opacity(0.5))
                    }
                }
                .frame(height: 200)
            }

            // Content area
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header with metadata
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(doItem.timestamp, format: .dateTime.month(.wide).day().year())
                                .font(.system(size: 16, weight: .semibold))
                            Text(doItem.timestamp, format: .dateTime.hour().minute())
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Duration badge
                        if doItem.duration > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "video")
                                    .font(.system(size: 11))
                                Text(doItem.duration.formatTiming())
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.secondary.opacity(0.15))
                            )
                            .foregroundColor(.secondary)
                        }

                        // Copy button
                        Button(action: {
                            let textToCopy = doItem.enhancedText ?? doItem.text
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(textToCopy, forType: .string)
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        // Show in Finder button
                        if let url = videoURL {
                            Button(action: {
                                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                            }) {
                                Image(systemName: "folder")
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Show video in Finder")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    Divider()
                        .padding(.horizontal, 16)

                    // Transcription section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Transcription")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)

                        // Main transcription text
                        Text(doItem.enhancedText ?? doItem.text)
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(.thinMaterial)
                            )

                        // Show original if enhanced exists
                        if doItem.enhancedText != nil {
                            DisclosureGroup {
                                Text(doItem.text)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .lineSpacing(3)
                                    .textSelection(.enabled)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.secondary.opacity(0.08))
                                    )
                            } label: {
                                Text("Original transcription")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    // Video Description section - always show if video exists
                    if hasVideoFile {
                        Divider()
                            .padding(.horizontal, 16)

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Video Description")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.secondary)

                                Spacer()

                                // Status indicator or generate button
                                if isGeneratingDescription || doItem.videoDescriptionStatus == VideoDescriptionStatus.processing.rawValue || doItem.videoDescriptionStatus == VideoDescriptionStatus.pending.rawValue {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("Analyzing...")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                } else if doItem.videoDescription == nil {
                                    // Show generate button when no description exists
                                    Button(action: {
                                        Task {
                                            await generateVideoDescription()
                                        }
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "wand.and.stars")
                                                .font(.system(size: 11))
                                            Text(doItem.videoDescriptionStatus == VideoDescriptionStatus.failed.rawValue ? "Retry" : "Describe")
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }

                            if let description = doItem.videoDescription {
                                Text(markdownToAttributedString(description))
                                    .font(.system(size: 14))
                                    .lineSpacing(4)
                                    .textSelection(.enabled)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(.thinMaterial)
                                    )
                            } else if doItem.videoDescriptionStatus == VideoDescriptionStatus.failed.rawValue && !isGeneratingDescription {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundColor(.orange)
                                    Text(doItem.videoDescriptionError ?? "Analysis failed")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)

                                    Spacer()
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.orange.opacity(0.1))
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Metadata footer
                    if let modelName = doItem.transcriptionModelName {
                        HStack(spacing: 8) {
                            Image(systemName: "cpu")
                                .font(.system(size: 10))
                            Text(modelName)
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Markdown Rendering

    private func markdownToAttributedString(_ markdown: String) -> AttributedString {
        do {
            let attributed = try AttributedString(markdown: markdown, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            return attributed
        } catch {
            // Fallback to plain text if markdown parsing fails
            return AttributedString(markdown)
        }
    }

    // MARK: - Video Description Generation

    private func generateVideoDescription() async {
        guard let url = videoURL else { return }

        isGeneratingDescription = true
        doItem.videoDescriptionStatus = VideoDescriptionStatus.processing.rawValue
        doItem.videoDescriptionError = nil
        try? modelContext.save()

        do {
            let result = try await VideoAnalysisService.shared.analyzeVideo(at: url)

            await MainActor.run {
                doItem.videoDescription = result.description
                doItem.videoDescriptionStatus = VideoDescriptionStatus.completed.rawValue
                doItem.videoDescriptionModelName = result.modelName
                try? modelContext.save()
                isGeneratingDescription = false

                NotificationCenter.default.post(name: .doDescriptionUpdated, object: doItem)
            }
        } catch {
            await MainActor.run {
                doItem.videoDescriptionStatus = VideoDescriptionStatus.failed.rawValue
                doItem.videoDescriptionError = error.localizedDescription
                try? modelContext.save()
                isGeneratingDescription = false

                NotificationCenter.default.post(name: .doDescriptionUpdated, object: doItem)
            }
        }
    }
}
