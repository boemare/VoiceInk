import SwiftUI

struct MiniRecorderView: View {
    @ObservedObject var whisperState: WhisperState
    @ObservedObject var recorder: Recorder
    @EnvironmentObject var windowManager: MiniWindowManager

    private var borderColor: Color {
        if whisperState.isDosMode {
            return .red
        } else if whisperState.isNotesMode {
            return .blue
        } else {
            return .cream.opacity(0.3)
        }
    }

    private var leftIcon: String? {
        if whisperState.isDosMode {
            return "video.fill"
        } else if whisperState.isNotesMode {
            return "note.text"
        } else {
            return nil
        }
    }

    private var rightIcon: String? {
        if whisperState.isDosMode {
            return "record.circle"
        } else if whisperState.isNotesMode {
            return "pencil"
        } else {
            return nil
        }
    }

    private var visualizerColor: Color {
        if whisperState.isDosMode {
            return .red
        } else if whisperState.isNotesMode {
            return .blue
        } else {
            return .cream
        }
    }

    private var backgroundView: some View {
        Color.black
            .clipShape(Capsule())
    }

    private var statusView: some View {
        RecorderStatusDisplay(
            currentState: whisperState.recordingState,
            audioMeter: recorder.audioMeter,
            color: visualizerColor
        )
    }

    private var contentLayout: some View {
        HStack(spacing: 0) {
            if let icon = leftIcon {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(borderColor)
                    .frame(width: 28)
                    .padding(.leading, 7)
            }

            Spacer()

            statusView
                .frame(maxWidth: .infinity)

            Spacer()

            if let icon = rightIcon {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(borderColor)
                    .frame(width: 28)
                    .padding(.trailing, 7)
            }
        }
        .padding(.vertical, 9)
    }

    private var recorderCapsule: some View {
        Capsule()
            .fill(.clear)
            .background(backgroundView)
            .overlay {
                Capsule()
                    .strokeBorder(borderColor, lineWidth: whisperState.isDosMode || whisperState.isNotesMode ? 2.5 : 0.5)
            }
            .overlay {
                contentLayout
            }
    }

    private var modeIdentifier: String {
        if whisperState.isDosMode {
            return "dos"
        } else if whisperState.isNotesMode {
            return "notes"
        } else {
            return "normal"
        }
    }

    var body: some View {
        Group {
            if windowManager.isVisible {
                recorderCapsule
                    .id(modeIdentifier)
                    .animation(.easeInOut(duration: 0.2), value: modeIdentifier)
            }
        }
    }
}
