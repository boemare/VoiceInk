import Foundation
import AVFoundation
import CoreAudio
import os

/// Orchestrates meeting recording by capturing both microphone and system audio
@MainActor
class MeetingRecorderService: NSObject, ObservableObject {

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MeetingRecorder")

    // Child recorders
    private var micRecorder: CoreAudioRecorder?
    private var systemAudioCapture: SystemAudioCaptureService?

    // State
    @Published var isRecording = false
    @Published var micMeter = AudioMeter(averagePower: 0, peakPower: 0)
    @Published var systemMeter = AudioMeter(averagePower: 0, peakPower: 0)
    @Published var recordingDuration: TimeInterval = 0
    @Published var recordingError: String?

    // File URLs for current session
    private var sessionID: UUID?
    private var micAudioURL: URL?
    private var systemAudioURL: URL?
    private var mixedAudioURL: URL?
    private var recordingStartTime: Date?

    // Tasks
    private var meterUpdateTask: Task<Void, Never>?
    private var durationUpdateTask: Task<Void, Never>?

    // Dependencies
    private let deviceManager = AudioDeviceManager.shared

    // Directory for meeting recordings
    private let meetingsDirectory: URL

    override init() {
        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")
        self.meetingsDirectory = appSupportDirectory.appendingPathComponent("Meetings")
        super.init()
        createDirectoryIfNeeded()
    }

    private func createDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(at: meetingsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public Interface

    /// Start recording both microphone and system audio
    func startRecording() async throws -> UUID {
        guard !isRecording else {
            throw MeetingRecorderError.alreadyRecording
        }

        let newSessionID = UUID()
        sessionID = newSessionID

        // Create session directory
        let sessionDir = meetingsDirectory.appendingPathComponent(newSessionID.uuidString)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        // Set up file paths
        micAudioURL = sessionDir.appendingPathComponent("mic.wav")
        systemAudioURL = sessionDir.appendingPathComponent("system.wav")
        mixedAudioURL = sessionDir.appendingPathComponent("mixed.wav")

        logger.info("Starting meeting recording session: \(newSessionID.uuidString)")

        do {
            // Start microphone recording
            try await startMicrophoneRecording()

            // Start system audio capture
            try await startSystemAudioCapture()

            isRecording = true
            recordingStartTime = Date()
            recordingError = nil

            // Start meter updates
            startMeterUpdates()

            // Start duration timer
            startDurationTimer()

            logger.info("Meeting recording started successfully")

            return newSessionID

        } catch {
            // Clean up on failure
            await cleanup()
            throw error
        }
    }

    /// Stop recording and return the result with file URLs
    func stopRecording() async throws -> MeetingRecordingResult {
        guard isRecording else {
            throw MeetingRecorderError.notRecording
        }

        logger.info("Stopping meeting recording")

        isRecording = false

        // Stop meter and duration updates
        meterUpdateTask?.cancel()
        durationUpdateTask?.cancel()

        // Stop microphone recording
        micRecorder?.stopRecording()
        micRecorder = nil

        // Stop system audio capture
        try? await systemAudioCapture?.stopCapture()
        systemAudioCapture = nil

        // Calculate final duration
        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? recordingDuration

        // Mix the audio tracks
        do {
            try await mixAudioTracks()
        } catch {
            logger.error("Failed to mix audio tracks: \(error.localizedDescription)")
            // Continue without mixed audio
        }

        // Reset meters
        micMeter = AudioMeter(averagePower: 0, peakPower: 0)
        systemMeter = AudioMeter(averagePower: 0, peakPower: 0)
        recordingDuration = 0
        recordingStartTime = nil

        let result = MeetingRecordingResult(
            sessionID: sessionID ?? UUID(),
            micAudioURL: micAudioURL,
            systemAudioURL: systemAudioURL,
            mixedAudioURL: mixedAudioURL,
            duration: duration
        )

        logger.info("Meeting recording stopped. Duration: \(duration)s")

        return result
    }

    /// Cancel recording and clean up files
    func cancelRecording() async {
        guard isRecording else { return }

        logger.info("Cancelling meeting recording")

        isRecording = false
        meterUpdateTask?.cancel()
        durationUpdateTask?.cancel()

        micRecorder?.stopRecording()
        micRecorder = nil

        try? await systemAudioCapture?.stopCapture()
        systemAudioCapture = nil

        // Delete session directory
        if let sessionID = sessionID {
            let sessionDir = meetingsDirectory.appendingPathComponent(sessionID.uuidString)
            try? FileManager.default.removeItem(at: sessionDir)
        }

        await cleanup()
    }

    // MARK: - Private Methods

    private func startMicrophoneRecording() async throws {
        guard let url = micAudioURL else {
            throw MeetingRecorderError.invalidConfiguration
        }

        let deviceID = deviceManager.getCurrentDevice()

        let recorder = CoreAudioRecorder()
        micRecorder = recorder

        try recorder.startRecording(toOutputFile: url, deviceID: deviceID)

        logger.info("Microphone recording started")
    }

    private func startSystemAudioCapture() async throws {
        guard let url = systemAudioURL else {
            throw MeetingRecorderError.invalidConfiguration
        }

        let capture = SystemAudioCaptureService()
        systemAudioCapture = capture

        try await capture.startCapture(toURL: url)

        logger.info("System audio capture started")
    }

    private func startMeterUpdates() {
        meterUpdateTask = Task {
            while isRecording && !Task.isCancelled {
                updateMeters()
                try? await Task.sleep(nanoseconds: 17_000_000)  // ~60fps
            }
        }
    }

    private func updateMeters() {
        // Update microphone meter
        if let recorder = micRecorder {
            let avgPower = recorder.averagePower
            let peakPower = recorder.peakPower
            micMeter = normalizedMeter(average: avgPower, peak: peakPower)
        }

        // Update system audio meter
        if let capture = systemAudioCapture {
            let avgPower = capture.averagePower
            let peakPower = capture.peakPower
            systemMeter = normalizedMeter(average: avgPower, peak: peakPower)
        }
    }

    private func normalizedMeter(average: Float, peak: Float) -> AudioMeter {
        let minDb: Float = -60.0
        let maxDb: Float = 0.0

        let normalizedAverage: Float
        if average < minDb {
            normalizedAverage = 0.0
        } else if average >= maxDb {
            normalizedAverage = 1.0
        } else {
            normalizedAverage = (average - minDb) / (maxDb - minDb)
        }

        let normalizedPeak: Float
        if peak < minDb {
            normalizedPeak = 0.0
        } else if peak >= maxDb {
            normalizedPeak = 1.0
        } else {
            normalizedPeak = (peak - minDb) / (maxDb - minDb)
        }

        return AudioMeter(averagePower: Double(normalizedAverage), peakPower: Double(normalizedPeak))
    }

    private func startDurationTimer() {
        durationUpdateTask = Task {
            while isRecording && !Task.isCancelled {
                if let startTime = recordingStartTime {
                    recordingDuration = Date().timeIntervalSince(startTime)
                }
                try? await Task.sleep(nanoseconds: 100_000_000)  // Update every 100ms
            }
        }
    }

    private func mixAudioTracks() async throws {
        guard let micURL = micAudioURL,
              let sysURL = systemAudioURL,
              let mixURL = mixedAudioURL else {
            return
        }

        // Check both files exist
        guard FileManager.default.fileExists(atPath: micURL.path),
              FileManager.default.fileExists(atPath: sysURL.path) else {
            logger.warning("Cannot mix: one or both audio files missing")
            return
        }

        logger.info("Mixing audio tracks")

        // Read both WAV files
        let micSamples = try readWAVSamples(from: micURL)
        let sysSamples = try readWAVSamples(from: sysURL)

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
        try writeWAVFile(samples: mixedSamples, to: mixURL)

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

    private func cleanup() async {
        micRecorder = nil
        systemAudioCapture = nil
        sessionID = nil
        micAudioURL = nil
        systemAudioURL = nil
        mixedAudioURL = nil
        recordingStartTime = nil
        recordingDuration = 0
        micMeter = AudioMeter(averagePower: 0, peakPower: 0)
        systemMeter = AudioMeter(averagePower: 0, peakPower: 0)
    }

    deinit {
        meterUpdateTask?.cancel()
        durationUpdateTask?.cancel()
    }
}

// MARK: - Result Type

struct MeetingRecordingResult {
    let sessionID: UUID
    let micAudioURL: URL?
    let systemAudioURL: URL?
    let mixedAudioURL: URL?
    let duration: TimeInterval
}

// MARK: - Error Types

enum MeetingRecorderError: LocalizedError {
    case alreadyRecording
    case notRecording
    case invalidConfiguration
    case microphoneError(String)
    case systemAudioError(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "A meeting recording is already in progress"
        case .notRecording:
            return "No meeting recording in progress"
        case .invalidConfiguration:
            return "Invalid recording configuration"
        case .microphoneError(let msg):
            return "Microphone error: \(msg)"
        case .systemAudioError(let msg):
            return "System audio error: \(msg)"
        }
    }
}
