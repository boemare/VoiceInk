import SwiftUI

struct NoteListItem: View {
    let note: Note
    let isSelected: Bool
    let isChecked: Bool
    let onSelect: () -> Void
    let onToggleCheck: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { isChecked },
                set: { _ in onToggleCheck() }
            ))
            .toggleStyle(NoteCheckboxStyle())
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                // Title - first line of note
                Text(noteTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                // Preview text
                if let preview = notePreview {
                    Text(preview)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // Metadata row
                HStack(spacing: 6) {
                    Text(relativeTimestamp)
                        .font(.system(size: 11))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))

                    // Audio indicators
                    if hasMicAudio || hasSystemAudio {
                        HStack(spacing: 4) {
                            if hasMicAudio {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 9))
                            }
                            if hasSystemAudio {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 9))
                            }
                        }
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    }

                    if note.isMeeting, let sourceApp = note.sourceApp {
                        Text(sourceApp)
                            .font(.system(size: 10))
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    }

                    if note.duration > 0 {
                        Text(note.duration.formatTiming())
                            .font(.system(size: 10))
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }

    private var noteTitle: String {
        let text = note.enhancedText ?? note.text
        let firstLine = text.components(separatedBy: .newlines).first ?? text
        return String(firstLine.prefix(60))
    }

    private var notePreview: String? {
        let text = note.enhancedText ?? note.text
        let lines = text.components(separatedBy: .newlines)
        guard lines.count > 1 else { return nil }
        let preview = lines.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return preview.isEmpty ? nil : String(preview.prefix(80))
    }

    private var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: note.timestamp, relativeTo: Date())
    }

    private var hasMicAudio: Bool {
        note.audioFileURL != nil && !note.audioFileURL!.isEmpty
    }

    private var hasSystemAudio: Bool {
        note.systemAudioFileURL != nil && !note.systemAudioFileURL!.isEmpty
    }
}

struct NoteCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: {
            configuration.isOn.toggle()
        }) {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundColor(configuration.isOn ? .accentColor : Color(NSColor.quaternaryLabelColor))
        }
        .buttonStyle(.plain)
    }
}
