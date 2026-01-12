import SwiftUI

struct DoListItem: View {
    let doItem: Do
    let isSelected: Bool
    let isChecked: Bool
    let onSelect: () -> Void
    let onToggleCheck: () -> Void

    private var thumbnailImage: NSImage? {
        guard let data = doItem.thumbnailData else { return nil }
        return NSImage(data: data)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Checkbox
            Toggle("", isOn: Binding(
                get: { isChecked },
                set: { _ in onToggleCheck() }
            ))
            .toggleStyle(DoCheckboxStyle())
            .labelsHidden()

            // Thumbnail preview - larger for video content
            ZStack {
                if let image = thumbnailImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 50)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.black.opacity(0.8))
                        .overlay(
                            Image(systemName: "video.fill")
                                .foregroundColor(.white.opacity(0.4))
                                .font(.system(size: 16))
                        )
                }

                // Duration overlay
                if doItem.duration > 0 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(doItem.duration.formatTiming())
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(3)
                                .padding(3)
                        }
                    }
                }
            }
            .frame(width: 80, height: 50)
            .cornerRadius(6)

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(doItem.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Text(doItem.enhancedText ?? doItem.text)
                    .font(.system(size: 12, weight: .regular))
                    .lineLimit(2)
                    .foregroundColor(.primary)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
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
}

struct DoCheckboxStyle: ToggleStyle {
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
