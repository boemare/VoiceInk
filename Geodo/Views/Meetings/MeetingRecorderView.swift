import SwiftUI

struct MeetingRecorderView: View {
    @ObservedObject var recorder: MeetingRecorderService
    var onRecordingComplete: (MeetingRecordingResult) -> Void

    @State private var isStarting = false
    @State private var isStopping = false

    var body: some View {
        VStack(spacing: 12) {
            if recorder.isRecording {
                // Recording in progress
                VStack(spacing: 10) {
                    // Duration display
                    HStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .opacity(pulsingOpacity)

                        Text(formatDuration(recorder.recordingDuration))
                            .font(.system(size: 24, weight: .medium, design: .monospaced))
                            .foregroundColor(.cream)
                    }

                    // Dual audio meters
                    HStack(spacing: 16) {
                        AudioMeterView(
                            label: "Mic",
                            level: recorder.micMeter.averagePower,
                            icon: "mic.fill"
                        )

                        AudioMeterView(
                            label: "System",
                            level: recorder.systemMeter.averagePower,
                            icon: "speaker.wave.2.fill"
                        )
                    }

                    // Stop button
                    Button(action: {
                        Task { await stopRecording() }
                    }) {
                        HStack(spacing: 8) {
                            if isStopping {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "stop.fill")
                            }
                            Text(isStopping ? "Stopping..." : "Stop Recording")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.red)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isStopping)
                }
            } else {
                // Not recording - show start button
                VStack(spacing: 10) {
                    Text("Meeting Recorder")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)

                    Text("Records both your microphone and system audio")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button(action: {
                        Task { await startRecording() }
                    }) {
                        HStack(spacing: 8) {
                            if isStarting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "record.circle")
                            }
                            Text(isStarting ? "Starting..." : "Start Recording")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.accentColor)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isStarting)
                }
            }

            // Error display
            if let error = recorder.recordingError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    @State private var pulsingOpacity: Double = 1.0

    private func startRecording() async {
        isStarting = true
        defer { isStarting = false }

        do {
            _ = try await recorder.startRecording()

            // Start pulsing animation
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulsingOpacity = 0.3
            }
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    private func stopRecording() async {
        isStopping = true
        defer { isStopping = false }

        // Stop pulsing
        withAnimation {
            pulsingOpacity = 1.0
        }

        do {
            let result = try await recorder.stopRecording()
            onRecordingComplete(result)
        } catch {
            print("Failed to stop recording: \(error)")
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) / 60 % 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

struct AudioMeterView: View {
    let label: String
    let level: Double
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.secondary)

            // Meter bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.secondary.opacity(0.2))

                    // Level indicator
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(meterColor(for: level))
                        .frame(width: geometry.size.width * CGFloat(min(level, 1.0)))
                        .animation(.linear(duration: 0.05), value: level)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
    }

    private func meterColor(for level: Double) -> Color {
        if level > 0.9 {
            return .red
        } else if level > 0.7 {
            return .orange
        } else if level > 0.3 {
            return .green
        } else {
            return .green.opacity(0.7)
        }
    }
}
