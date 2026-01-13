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

    private var showLiveTranscript: Bool {
        whisperState.isNotesMode &&
        whisperState.isLiveTranscriptionEnabled &&
        whisperState.recordingState == .recording
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
            return "do's"
        } else if whisperState.isNotesMode {
            return "notes"
        } else {
            return "normal"
        }
    }

    var body: some View {
        Group {
            if windowManager.isVisible {
                VStack(spacing: 8) {
                    recorderCapsule
                        .id(modeIdentifier)
                        .animation(.easeInOut(duration: 0.2), value: modeIdentifier)

                    // Live transcription panel
                    if showLiveTranscript {
                        liveTranscriptPanel
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: showLiveTranscript)
            }
        }
    }

    private var liveTranscriptPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
                    .overlay(
                        Circle()
                            .fill(.red.opacity(0.4))
                            .frame(width: 12, height: 12)
                            .scaleEffect(1.2)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: true)
                    )
                Text("Live")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                if !recorder.liveChunks.isEmpty {
                    Text("\(recorder.liveChunks.count)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.15))
                        )
                }
            }

            // Transcript content
            if recorder.liveTranscript.isEmpty {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Listening...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else {
                ScrollView {
                    Text(recorder.liveTranscript)
                        .font(.system(size: 12))
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 80)
            }
        }
        .padding(10)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.2), radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
}
