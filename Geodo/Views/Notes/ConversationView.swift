import SwiftUI

/// Displays a conversation with speaker-labeled segments in chat bubble style
struct ConversationView: View {
    let segments: [TranscriptionSegment]
    let speakerMap: [String: String]?

    private var speakerColors: [String: Color] {
        generateSpeakerColors(from: segments)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(segments) { segment in
                    ConversationBubble(
                        segment: segment,
                        displayName: speakerMap?[segment.speakerId] ?? segment.speakerId,
                        color: speakerColors[segment.speakerId] ?? .gray
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func generateSpeakerColors(from segments: [TranscriptionSegment]) -> [String: Color] {
        let uniqueSpeakers = Set(segments.map { $0.speakerId })
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .mint, .indigo]

        var result: [String: Color] = ["Me": .accentColor]
        for (index, speaker) in uniqueSpeakers.filter({ $0 != "Me" }).sorted().enumerated() {
            result[speaker] = colors[index % colors.count]
        }
        return result
    }
}

/// Individual conversation bubble for a speaker segment
struct ConversationBubble: View {
    let segment: TranscriptionSegment
    let displayName: String
    let color: Color

    @State private var justCopied = false

    private var isMe: Bool {
        segment.speakerId == "Me"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if !isMe { Spacer(minLength: 40) }

            VStack(alignment: isMe ? .leading : .trailing, spacing: 4) {
                // Speaker label with timestamp
                HStack(spacing: 6) {
                    if !isMe {
                        Spacer()
                    }

                    Text(displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(color)

                    Text(formatTime(segment.startTime))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    if isMe {
                        Spacer()
                    }
                }

                // Message bubble
                HStack(alignment: .bottom, spacing: 4) {
                    if !isMe { Spacer() }

                    Text(segment.text)
                        .font(.system(size: 14))
                        .lineSpacing(2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(bubbleColor)
                        )
                        .textSelection(.enabled)

                    // Copy button
                    Button(action: copyToClipboard) {
                        Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundColor(justCopied ? .green : .secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .opacity(0.8)

                    if isMe { Spacer() }
                }
            }

            if isMe { Spacer(minLength: 40) }
        }
    }

    private var bubbleColor: Color {
        if isMe {
            return Color.accentColor.opacity(0.2)
        } else {
            return color.opacity(0.15)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(segment.text, forType: .string)

        withAnimation {
            justCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                justCopied = false
            }
        }
    }
}

/// Editor for assigning names to speakers
struct SpeakerLabelEditor: View {
    @Binding var speakerMap: [String: String]
    let segments: [TranscriptionSegment]

    private var uniqueSpeakers: [String] {
        Array(Set(segments.map { $0.speakerId }))
            .filter { $0 != "Me" }
            .sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Speaker Labels")
                .font(.headline)

            Text("Assign names to identified speakers")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(uniqueSpeakers, id: \.self) { speakerId in
                HStack(spacing: 12) {
                    Text(speakerId)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    TextField("Name", text: Binding(
                        get: { speakerMap[speakerId] ?? "" },
                        set: { speakerMap[speakerId] = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 150)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}
