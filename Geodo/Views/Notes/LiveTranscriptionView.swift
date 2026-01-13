import SwiftUI

/// View that displays live transcription during recording
struct LiveTranscriptionView: View {
    let chunks: [TranscribedChunk]
    let isRecording: Bool

    @State private var scrollToBottom = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    if isRecording {
                        LivePulsingDot()
                    }
                    Text("Live Transcription")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !chunks.isEmpty {
                    Text("\(chunks.count) chunks")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))

            Divider()

            // Content
            if chunks.isEmpty {
                emptyState
            } else {
                transcriptContent
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            if isRecording {
                ProgressView()
                    .controlSize(.small)
                Text("Listening...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("Start speaking to see live transcription")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var transcriptContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(chunks) { chunk in
                        ChunkBubble(chunk: chunk)
                            .id(chunk.id)
                    }

                    // Anchor for scrolling to bottom
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(12)
            }
            .onChange(of: chunks.count) { _, _ in
                if scrollToBottom {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
    }
}

private struct ChunkBubble: View {
    let chunk: TranscribedChunk

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Timestamp
            Text(formatTimeRange(chunk.startTime, chunk.endTime))
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary.opacity(0.6))

            // Text
            Text(chunk.text)
                .font(.system(size: 13))
                .lineSpacing(2)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.1))
        )
    }

    private func formatTimeRange(_ start: TimeInterval, _ end: TimeInterval) -> String {
        let startStr = formatTime(start)
        let endStr = formatTime(end)
        return "\(startStr) - \(endStr)"
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Pulsing Dot Animation

private struct LivePulsingDot: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .fill(.red.opacity(0.5))
                    .frame(width: 16, height: 16)
                    .scaleEffect(isAnimating ? 1.2 : 0.8)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Compact Live Transcript Display

/// Compact view showing the latest transcribed text (for mini recorder)
struct LiveTranscriptCompact: View {
    let transcript: String
    let isRecording: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isRecording && transcript.isEmpty {
                ProgressView()
                    .controlSize(.mini)
                Text("Listening...")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else if !transcript.isEmpty {
                Text(transcript)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .truncationMode(.head)
                    .foregroundColor(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview("Live Transcription View") {
    LiveTranscriptionView(
        chunks: [
            TranscribedChunk(text: "Hello, this is the first chunk of transcribed text.", startTime: 0, endTime: 4, chunkIndex: 0),
            TranscribedChunk(text: "And here is the second chunk with more content.", startTime: 4, endTime: 8, chunkIndex: 1),
            TranscribedChunk(text: "The transcription continues as you speak.", startTime: 8, endTime: 12, chunkIndex: 2)
        ],
        isRecording: true
    )
    .frame(width: 300, height: 250)
    .padding()
}
