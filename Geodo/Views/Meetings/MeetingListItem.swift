import SwiftUI

struct MeetingListItem: View {
    let meeting: Meeting
    let isSelected: Bool
    let isChecked: Bool
    let onSelect: () -> Void
    let onToggleCheck: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { isChecked },
                set: { _ in onToggleCheck() }
            ))
            .toggleStyle(MeetingCheckboxStyle())
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    // Title or date
                    if let title = meeting.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }

                    Text(meeting.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    Spacer()

                    if meeting.duration > 0 {
                        Text(meeting.duration.formatTiming())
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.secondary.opacity(0.1))
                            )
                            .foregroundColor(.secondary)
                    }
                }

                // Source app badge if available
                if let sourceApp = meeting.sourceApp {
                    HStack(spacing: 4) {
                        Image(systemName: iconForApp(sourceApp))
                            .font(.system(size: 9))
                        Text(sourceApp)
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.accentColor.opacity(0.1))
                    )
                }

                // Preview text
                Text(meeting.enhancedText ?? meeting.text)
                    .font(.system(size: 12, weight: .regular))
                    .lineLimit(2)
                    .foregroundColor(.cream)
            }
        }
        .padding(10)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(NSColor.selectedContentBackgroundColor).opacity(0.3))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.thinMaterial)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }

    private func iconForApp(_ app: String) -> String {
        switch app.lowercased() {
        case "zoom":
            return "video.fill"
        case "google meet", "meet":
            return "video.fill"
        case "microsoft teams", "teams":
            return "person.2.fill"
        case "facetime":
            return "video.fill"
        case "slack":
            return "number"
        default:
            return "app.fill"
        }
    }
}

struct MeetingCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: {
            configuration.isOn.toggle()
        }) {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(configuration.isOn ? Color(NSColor.controlAccentColor) : .secondary)
                .font(.system(size: 18))
        }
        .buttonStyle(.plain)
    }
}
