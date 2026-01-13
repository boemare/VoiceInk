import SwiftUI

struct MeetingDetailView: View {
    let meeting: Meeting

    private var hasMixedAudio: Bool {
        if let urlString = meeting.mixedAudioFileURL,
           let url = URL(string: urlString),
           FileManager.default.fileExists(atPath: url.path) {
            return true
        }
        return false
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let title = meeting.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 18, weight: .semibold))
                    } else {
                        Text("Meeting")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    Text(meeting.timestamp, format: .dateTime.month(.wide).day().year().hour().minute())
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()

                // Source app badge
                if let sourceApp = meeting.sourceApp {
                    Text(sourceApp)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.accentColor.opacity(0.15))
                        )
                        .foregroundColor(.accentColor)
                }

                // Copy button
                Button(action: {
                    let textToCopy = meeting.enhancedText ?? meeting.text
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(textToCopy, forType: .string)
                }) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Divider()
                .padding(.horizontal, 16)

            ScrollView {
                VStack(spacing: 16) {
                    MeetingBubble(
                        label: "Transcript",
                        text: meeting.text,
                        isEnhanced: false
                    )

                    if let enhancedText = meeting.enhancedText {
                        MeetingBubble(
                            label: "Summary",
                            text: enhancedText,
                            isEnhanced: true
                        )
                    }
                }
                .padding(16)
            }

            if hasMixedAudio, let urlString = meeting.mixedAudioFileURL,
               let url = URL(string: urlString) {
                VStack(spacing: 0) {
                    Divider()

                    AudioPlayerView(url: url)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }
            }

            // Metadata footer
            HStack(spacing: 16) {
                if meeting.duration > 0 {
                    Label(meeting.duration.formatTiming(), systemImage: "clock")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                if let modelName = meeting.transcriptionModelName {
                    Label(modelName, systemImage: "cpu")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                // Show participant count if available
                if let participants = meeting.participants, !participants.isEmpty {
                    Label("\(participants.count) participants", systemImage: "person.2")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

private struct MeetingBubble: View {
    let label: String
    let text: String
    let isEnhanced: Bool
    @State private var justCopied = false

    var body: some View {
        HStack(alignment: .bottom) {
            if isEnhanced { Spacer(minLength: 60) }

            VStack(alignment: isEnhanced ? .leading : .trailing, spacing: 4) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.horizontal, 12)

                ScrollView {
                    Text(text)
                        .font(.system(size: 14, weight: .regular))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                .frame(maxHeight: 350)
                .background {
                    if isEnhanced {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.accentColor.opacity(0.2))
                    } else {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.thinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Color.cream.opacity(0.06), lineWidth: 0.5)
                            )
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Button(action: {
                        copyToClipboard(text)
                    }) {
                        Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundColor(justCopied ? .green : .secondary)
                            .frame(width: 28, height: 28)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.9))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Copy to clipboard")
                    .padding(8)
                }
            }

            if !isEnhanced { Spacer(minLength: 60) }
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

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
