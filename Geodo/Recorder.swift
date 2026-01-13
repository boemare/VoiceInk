import Foundation
import AVFoundation
import CoreAudio
import os

@MainActor
class Recorder: NSObject, ObservableObject {
    private var recorder: CoreAudioRecorder?
    private var systemAudioCapture: SystemAudioCaptureService?
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "Recorder")
    private let deviceManager = AudioDeviceManager.shared
    private var deviceObserver: NSObjectProtocol?
    private var deviceSwitchObserver: NSObjectProtocol?
    private var isReconfiguring = false
    private let mediaController = MediaController.shared
    private let playbackController = PlaybackController.shared
    @Published var audioMeter = AudioMeter(averagePower: 0, peakPower: 0)
    @Published var systemAudioMeter = AudioMeter(averagePower: 0, peakPower: 0)
    @Published var lastDualRecordingResult: DualRecordingResult?

    // Live transcription state
    @Published var liveTranscript: String = ""
    @Published var liveChunks: [TranscribedChunk] = []
    @Published var isLiveTranscriptionEnabled: Bool = false
    private var chunkedTranscriptionService: ChunkedTranscriptionService?
    private var transcriptionCallback: (([Float]) async throws -> String)?
    private var audioLevelCheckTask: Task<Void, Never>?
    private var audioMeterUpdateTask: Task<Void, Never>?
    private var audioRestorationTask: Task<Void, Never>?
    private var hasDetectedAudioInCurrentSession = false

    // Dual recording state
    private var isCapturingSystemAudio = false
    private var micAudioURL: URL?
    private var systemAudioURL: URL?
    private var finalOutputURL: URL?
    
    enum RecorderError: Error {
        case couldNotStartRecording
    }

    /// Result from dual-track recording (mic + system audio)
    struct DualRecordingResult {
        let micAudioURL: URL
        let systemAudioURL: URL?
    }

    /// Configure live transcription before starting recording
    /// - Parameter transcribe: Closure that takes Float samples and returns transcribed text
    func enableLiveTranscription(transcribe: @escaping ([Float]) async throws -> String) {
        self.transcriptionCallback = transcribe
        self.isLiveTranscriptionEnabled = true
        self.liveTranscript = ""
        self.liveChunks = []
        logger.info("Live transcription enabled")
    }

    /// Disable live transcription
    func disableLiveTranscription() {
        self.transcriptionCallback = nil
        self.isLiveTranscriptionEnabled = false
        logger.info("Live transcription disabled")
    }

    override init() {
        super.init()
        setupDeviceChangeObserver()
        setupDeviceSwitchObserver()
    }

    private func setupDeviceChangeObserver() {
        deviceObserver = AudioDeviceConfiguration.createDeviceChangeObserver { [weak self] in
            Task {
                await self?.handleDeviceChange()
            }
        }
    }

    private func setupDeviceSwitchObserver() {
        deviceSwitchObserver = NotificationCenter.default.addObserver(
            forName: .audioDeviceSwitchRequired,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task {
                await self?.handleDeviceSwitchRequired(notification)
            }
        }
    }

    private func handleDeviceChange() async {
        guard !isReconfiguring else { return }
        guard recorder != nil else { return }

        isReconfiguring = true

        try? await Task.sleep(nanoseconds: 200_000_000)

        await MainActor.run {
            NotificationCenter.default.post(name: .toggleMiniRecorder, object: nil)
        }

        isReconfiguring = false
    }

    private func handleDeviceSwitchRequired(_ notification: Notification) async {
        guard !isReconfiguring else { return }
        guard let recorder = recorder else { return }
        guard let userInfo = notification.userInfo,
              let newDeviceID = userInfo["newDeviceID"] as? AudioDeviceID else {
            logger.error("Device switch notification missing newDeviceID")
            return
        }

        // Prevent concurrent device switches and handleDeviceChange() interference
        isReconfiguring = true
        defer { isReconfiguring = false }

        logger.notice("🎙️ Device switch required: switching to device \(newDeviceID)")

        do {
            try recorder.switchDevice(to: newDeviceID)

            // Notify user about the switch
            if let deviceName = deviceManager.availableDevices.first(where: { $0.id == newDeviceID })?.name {
                await MainActor.run {
                    NotificationManager.shared.showNotification(
                        title: "Switched to: \(deviceName)",
                        type: .info
                    )
                }
            }

            logger.notice("🎙️ Successfully switched recording to device \(newDeviceID)")
        } catch {
            logger.error("❌ Failed to switch device: \(error.localizedDescription)")

            // If switch fails, stop recording and notify user
            await handleRecordingError(error)
        }
    }

    func startRecording(toOutputFile url: URL, captureSystemAudio: Bool = false, systemAudioOutputURL: URL? = nil) async throws {
        deviceManager.isRecordingActive = true

        let currentDeviceID = deviceManager.getCurrentDevice()
        let lastDeviceID = UserDefaults.standard.string(forKey: "lastUsedMicrophoneDeviceID")

        if String(currentDeviceID) != lastDeviceID {
            if let deviceName = deviceManager.availableDevices.first(where: { $0.id == currentDeviceID })?.name {
                await MainActor.run {
                    NotificationManager.shared.showNotification(
                        title: "Using: \(deviceName)",
                        type: .info
                    )
                }
            }
        }
        UserDefaults.standard.set(String(currentDeviceID), forKey: "lastUsedMicrophoneDeviceID")

        hasDetectedAudioInCurrentSession = false
        isCapturingSystemAudio = captureSystemAudio
        finalOutputURL = url
        lastDualRecordingResult = nil

        let deviceID = deviceManager.getCurrentDevice()

        do {
            let coreAudioRecorder = CoreAudioRecorder()
            recorder = coreAudioRecorder

            // If capturing system audio, write to provided URLs (permanent) or temp files (legacy)
            if captureSystemAudio {
                // Use provided URLs for permanent storage, or fall back to temp files
                if let sysURL = systemAudioOutputURL {
                    // New behavior: write directly to permanent paths
                    micAudioURL = url
                    systemAudioURL = sysURL
                } else {
                    // Legacy behavior: write to temp files for mixing
                    let tempDir = FileManager.default.temporaryDirectory
                    let sessionID = UUID().uuidString
                    micAudioURL = tempDir.appendingPathComponent("mic_\(sessionID).wav")
                    systemAudioURL = tempDir.appendingPathComponent("system_\(sessionID).wav")
                }

                try coreAudioRecorder.startRecording(toOutputFile: micAudioURL!, deviceID: deviceID)

                // Start system audio capture
                let capture = SystemAudioCaptureService()
                systemAudioCapture = capture
                try await capture.startCapture(toURL: systemAudioURL!)

                logger.info("Started dual recording (mic + system audio)")
            } else {
                try coreAudioRecorder.startRecording(toOutputFile: url, deviceID: deviceID)
            }

            // Set up live transcription if enabled
            if isLiveTranscriptionEnabled, let transcribeCallback = transcriptionCallback {
                liveTranscript = ""
                liveChunks = []

                let service = ChunkedTranscriptionService()
                chunkedTranscriptionService = service

                // Set up sample streaming from CoreAudioRecorder to ChunkedTranscriptionService
                coreAudioRecorder.setSampleStreamCallback { [weak self] samples in
                    guard let self = self else { return }
                    Task {
                        await service.feedSamples(samples)
                    }
                }

                // Start the chunked transcription service
                await service.start(
                    transcribe: transcribeCallback,
                    onChunk: { [weak self] chunk in
                        guard let self = self else { return }
                        Task { @MainActor in
                            self.liveChunks.append(chunk)
                            self.liveTranscript = self.liveChunks.map { $0.text }.joined(separator: " ")
                        }
                    }
                )

                logger.info("Live transcription started")
            }

            audioRestorationTask?.cancel()
            audioRestorationTask = nil

            // Only mute/pause media if NOT capturing system audio
            if !captureSystemAudio {
                Task { [weak self] in
                    guard let self = self else { return }
                    await self.playbackController.pauseMedia()
                    _ = await self.mediaController.muteSystemAudio()
                }
            }

            audioLevelCheckTask?.cancel()
            audioMeterUpdateTask?.cancel()

            audioMeterUpdateTask = Task {
                while recorder != nil && !Task.isCancelled {
                    updateAudioMeter()
                    if captureSystemAudio {
                        updateSystemAudioMeter()
                    }
                    try? await Task.sleep(nanoseconds: 17_000_000)
                }
            }

            audioLevelCheckTask = Task {
                let notificationChecks: [TimeInterval] = [5.0, 12.0]

                for delay in notificationChecks {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                    if Task.isCancelled { return }

                    if self.hasDetectedAudioInCurrentSession {
                        return
                    }

                    await MainActor.run {
                        NotificationManager.shared.showNotification(
                            title: "No Audio Detected",
                            type: .warning
                        )
                    }
                }
            }

        } catch {
            logger.error("Failed to create audio recorder: \(error.localizedDescription)")
            await stopRecordingAsync()
            throw RecorderError.couldNotStartRecording
        }
    }

    func stopRecording() {
        // For synchronous callers, start async cleanup but don't wait
        Task {
            await stopRecordingAsync()
        }
    }

    /// Async version of stopRecording that handles dual audio recording
    func stopRecordingAsync() async {
        audioLevelCheckTask?.cancel()
        audioMeterUpdateTask?.cancel()

        // Stop live transcription if running
        if let service = chunkedTranscriptionService {
            await service.stop()
            chunkedTranscriptionService = nil
            logger.info("Live transcription stopped")
        }

        // Clear sample stream callback before stopping recorder
        recorder?.setSampleStreamCallback(nil)
        recorder?.stopRecording()
        recorder = nil

        // Stop system audio capture if active
        if isCapturingSystemAudio {
            try? await systemAudioCapture?.stopCapture()
            systemAudioCapture = nil

            if let micURL = micAudioURL,
               let sysURL = systemAudioURL,
               let outputURL = finalOutputURL {
                // Check if we're using permanent paths (new behavior) or temp files (legacy)
                let usingPermanentPaths = micURL == outputURL

                if usingPermanentPaths {
                    // New behavior: keep both files separate, populate result
                    lastDualRecordingResult = DualRecordingResult(
                        micAudioURL: micURL,
                        systemAudioURL: sysURL
                    )
                    logger.info("Dual recording saved: mic=\(micURL.lastPathComponent), system=\(sysURL.lastPathComponent)")
                } else {
                    // Legacy behavior: mix audio tracks and delete temp files
                    do {
                        try await mixAudioTracks(micURL: micURL, systemURL: sysURL, outputURL: outputURL)
                        logger.info("Mixed audio saved to: \(outputURL.path)")
                    } catch {
                        logger.error("Failed to mix audio: \(error.localizedDescription)")
                        // Fall back to mic-only audio
                        try? FileManager.default.copyItem(at: micURL, to: outputURL)
                    }

                    // Clean up temp files
                    try? FileManager.default.removeItem(at: micURL)
                    try? FileManager.default.removeItem(at: sysURL)
                }
            }

            isCapturingSystemAudio = false
            micAudioURL = nil
            systemAudioURL = nil
            finalOutputURL = nil
        }

        audioMeter = AudioMeter(averagePower: 0, peakPower: 0)
        systemAudioMeter = AudioMeter(averagePower: 0, peakPower: 0)

        audioRestorationTask = Task {
            await mediaController.unmuteSystemAudio()
            await playbackController.resumeMedia()
        }
        deviceManager.isRecordingActive = false
    }

    private func handleRecordingError(_ error: Error) async {
        logger.error("❌ Recording error occurred: \(error.localizedDescription)")

        // Stop the recording
        stopRecording()

        // Notify the user about the recording failure
        await MainActor.run {
            NotificationManager.shared.showNotification(
                title: "Recording Failed: \(error.localizedDescription)",
                type: .error
            )
        }
    }

    private func updateAudioMeter() {
        guard let recorder = recorder else { return }

        let averagePower = recorder.averagePower
        let peakPower = recorder.peakPower

        let minVisibleDb: Float = -60.0
        let maxVisibleDb: Float = 0.0

        let normalizedAverage: Float
        if averagePower < minVisibleDb {
            normalizedAverage = 0.0
        } else if averagePower >= maxVisibleDb {
            normalizedAverage = 1.0
        } else {
            normalizedAverage = (averagePower - minVisibleDb) / (maxVisibleDb - minVisibleDb)
        }

        let normalizedPeak: Float
        if peakPower < minVisibleDb {
            normalizedPeak = 0.0
        } else if peakPower >= maxVisibleDb {
            normalizedPeak = 1.0
        } else {
            normalizedPeak = (peakPower - minVisibleDb) / (maxVisibleDb - minVisibleDb)
        }

        let newAudioMeter = AudioMeter(averagePower: Double(normalizedAverage), peakPower: Double(normalizedPeak))

        if !hasDetectedAudioInCurrentSession && newAudioMeter.averagePower > 0.01 {
            hasDetectedAudioInCurrentSession = true
        }

        audioMeter = newAudioMeter
    }

    private func updateSystemAudioMeter() {
        guard let capture = systemAudioCapture else { return }

        let averagePower = capture.averagePower
        let peakPower = capture.peakPower

        let minVisibleDb: Float = -60.0
        let maxVisibleDb: Float = 0.0

        let normalizedAverage: Float
        if averagePower < minVisibleDb {
            normalizedAverage = 0.0
        } else if averagePower >= maxVisibleDb {
            normalizedAverage = 1.0
        } else {
            normalizedAverage = (averagePower - minVisibleDb) / (maxVisibleDb - minVisibleDb)
        }

        let normalizedPeak: Float
        if peakPower < minVisibleDb {
            normalizedPeak = 0.0
        } else if peakPower >= maxVisibleDb {
            normalizedPeak = 1.0
        } else {
            normalizedPeak = (peakPower - minVisibleDb) / (maxVisibleDb - minVisibleDb)
        }

        systemAudioMeter = AudioMeter(averagePower: Double(normalizedAverage), peakPower: Double(normalizedPeak))
    }

    // MARK: - Audio Mixing

    private func mixAudioTracks(micURL: URL, systemURL: URL, outputURL: URL) async throws {
        // Check both files exist
        guard FileManager.default.fileExists(atPath: micURL.path),
              FileManager.default.fileExists(atPath: systemURL.path) else {
            logger.warning("Cannot mix: one or both audio files missing")
            // Just copy mic audio if system is missing
            if FileManager.default.fileExists(atPath: micURL.path) {
                try FileManager.default.copyItem(at: micURL, to: outputURL)
            }
            return
        }

        logger.info("Mixing audio tracks")

        // Read both WAV files
        let micSamples = try readWAVSamples(from: micURL)
        let sysSamples = try readWAVSamples(from: systemURL)

        guard !micSamples.isEmpty || !sysSamples.isEmpty else {
            logger.warning("Both audio files are empty")
            return
        }

        // Mix the samples
        let outputLength = max(micSamples.count, sysSamples.count)
        var mixedSamples = [Int16](repeating: 0, count: outputLength)

        for i in 0..<outputLength {
            let micSample = i < micSamples.count ? Float(micSamples[i]) : 0
            let sysSample = i < sysSamples.count ? Float(sysSamples[i]) : 0

            // Mix with headroom to prevent clipping
            let mixed = (micSample + sysSample) * 0.7
            let clipped = max(-32768.0, min(32767.0, mixed))
            mixedSamples[i] = Int16(clipped)
        }

        // Write mixed WAV file
        try writeWAVFile(samples: mixedSamples, to: outputURL)

        logger.info("Audio mixing complete: \(outputLength) samples")
    }

    private func readWAVSamples(from url: URL) throws -> [Int16] {
        let data = try Data(contentsOf: url)

        // WAV header is 44 bytes
        guard data.count > 44 else {
            return []
        }

        let audioData = data.dropFirst(44)
        let sampleCount = audioData.count / 2  // 16-bit samples

        var samples = [Int16](repeating: 0, count: sampleCount)
        audioData.withUnsafeBytes { ptr in
            let int16Ptr = ptr.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                samples[i] = int16Ptr[i]
            }
        }

        return samples
    }

    private func writeWAVFile(samples: [Int16], to url: URL) throws {
        var data = Data()

        // WAV header
        let sampleRate: UInt32 = 16000
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate: UInt32 = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = numChannels * (bitsPerSample / 8)
        let dataSize: UInt32 = UInt32(samples.count * 2)
        let fileSize: UInt32 = 36 + dataSize

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })  // Chunk size
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })   // PCM format
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        // Audio samples
        for sample in samples {
            data.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Array($0) })
        }

        try data.write(to: url)
    }

    // MARK: - Cleanup

    deinit {
        audioLevelCheckTask?.cancel()
        audioMeterUpdateTask?.cancel()
        audioRestorationTask?.cancel()
        if let observer = deviceObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = deviceSwitchObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

struct AudioMeter: Equatable {
    let averagePower: Double
    let peakPower: Double
}