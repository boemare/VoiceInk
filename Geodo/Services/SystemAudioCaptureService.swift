import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import os

/// Captures system audio output using ScreenCaptureKit (macOS 13+)
/// This captures audio from other applications (Zoom, Meet, etc.) without a virtual audio driver
final class SystemAudioCaptureService: NSObject, ObservableObject {

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "SystemAudioCapture")

    private var stream: SCStream?
    private var outputURL: URL?
    private var isCapturing = false

    // Audio file writing
    private var audioFile: AVAudioFile?
    private let audioQueue = DispatchQueue(label: "com.geodo.systemaudio", qos: .userInitiated)
    private let fileLock = NSLock()

    // Audio metering (thread-safe)
    private let meterLock = NSLock()
    private var _averagePower: Float = -160.0
    private var _peakPower: Float = -160.0

    var averagePower: Float {
        meterLock.lock()
        defer { meterLock.unlock() }
        return _averagePower
    }

    var peakPower: Float {
        meterLock.lock()
        defer { meterLock.unlock() }
        return _peakPower
    }

    // Sample rate conversion state
    private var inputSampleRate: Double = 48000.0
    private let outputSampleRate: Double = 16000.0
    private var resampleBuffer: [Float] = []

    override init() {
        super.init()
    }

    deinit {
        Task { [weak self] in
            try? await self?.stopCapture()
        }
    }

    // MARK: - Public Interface

    /// Check if the app has screen recording permission (required for system audio capture)
    static func hasPermission() async -> Bool {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return !content.displays.isEmpty
        } catch {
            return false
        }
    }

    /// Start capturing system audio to the specified file
    func startCapture(toURL url: URL) async throws {
        guard !isCapturing else {
            throw SystemAudioCaptureError.alreadyCapturing
        }

        // Check permission
        let hasPermission = await Self.hasPermission()
        if !hasPermission {
            logger.error("Screen recording permission not granted (required for system audio)")
            throw SystemAudioCaptureError.noPermission
        }

        // Get shareable content
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let display = content.displays.first else {
            throw SystemAudioCaptureError.noDisplayFound
        }

        outputURL = url

        // Configure stream for audio capture
        let config = SCStreamConfiguration()

        // Audio configuration
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true  // Don't capture our own app's audio
        config.sampleRate = 48000  // Capture at high quality, we'll downsample
        config.channelCount = 2    // Stereo capture, we'll mix to mono

        // Minimal video config (required but we won't use the frames)
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)  // 1 fps - minimal
        config.showsCursor = false

        // Create content filter for entire display
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        // Create stream
        stream = SCStream(filter: filter, configuration: config, delegate: self)

        guard let stream = stream else {
            throw SystemAudioCaptureError.streamCreationFailed
        }

        // Add audio output handler
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)

        // Create output audio file
        try createAudioFile(at: url)

        // Start capture
        try await stream.startCapture()
        isCapturing = true

        logger.info("System audio capture started: \(url.path)")
    }

    /// Stop capturing and return the output file URL
    func stopCapture() async throws -> URL? {
        guard isCapturing else { return nil }

        isCapturing = false

        do {
            try await stream?.stopCapture()
        } catch {
            logger.warning("Error stopping capture: \(error.localizedDescription)")
        }

        stream = nil

        // Close audio file and reset meters on a sync context
        closeFileAndResetMeters()

        logger.info("System audio capture stopped: \(self.outputURL?.path ?? "nil")")

        return outputURL
    }

    private func closeFileAndResetMeters() {
        fileLock.lock()
        audioFile = nil
        fileLock.unlock()

        meterLock.lock()
        _averagePower = -160.0
        _peakPower = -160.0
        meterLock.unlock()
    }

    var isCurrentlyCapturing: Bool { isCapturing }

    // MARK: - Private Methods

    private func createAudioFile(at url: URL) throws {
        // Remove existing file if any
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        // Create audio file with 16kHz mono format (for transcription)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: outputSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        fileLock.lock()
        defer { fileLock.unlock() }

        audioFile = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatInt16, interleaved: true)
    }

    private func processAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        // Get audio format
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else {
            return
        }

        inputSampleRate = asbd.mSampleRate
        let inputChannels = Int(asbd.mChannelsPerFrame)

        // Get audio buffer
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard status == kCMBlockBufferNoErr, let data = dataPointer else { return }

        // Convert to Float32 samples
        let sampleCount = length / MemoryLayout<Float32>.size
        let floatSamples = UnsafeBufferPointer(start: UnsafeRawPointer(data).assumingMemoryBound(to: Float32.self), count: sampleCount)

        // Calculate meters
        calculateMeters(from: Array(floatSamples))

        // Convert to mono
        let frameCount = sampleCount / inputChannels
        var monoSamples = [Float](repeating: 0, count: frameCount)

        for i in 0..<frameCount {
            var sum: Float = 0
            for ch in 0..<inputChannels {
                sum += floatSamples[i * inputChannels + ch]
            }
            monoSamples[i] = sum / Float(inputChannels)
        }

        // Resample from input sample rate to 16kHz
        let resampledSamples = resample(monoSamples, from: inputSampleRate, to: outputSampleRate)

        // Write to file
        writeToFile(samples: resampledSamples)
    }

    private func calculateMeters(from samples: [Float]) {
        guard !samples.isEmpty else { return }

        var sum: Float = 0
        var peak: Float = 0

        for sample in samples {
            let abs = abs(sample)
            sum += abs * abs
            if abs > peak {
                peak = abs
            }
        }

        let rms = sqrt(sum / Float(samples.count))
        let avgDb = 20.0 * log10(max(rms, 0.000001))
        let peakDb = 20.0 * log10(max(peak, 0.000001))

        meterLock.lock()
        _averagePower = avgDb
        _peakPower = peakDb
        meterLock.unlock()
    }

    private func resample(_ samples: [Float], from inputRate: Double, to outputRate: Double) -> [Int16] {
        guard inputRate != outputRate else {
            // No resampling needed, just convert to Int16
            return samples.map { sample in
                let scaled = sample * 32767.0
                let clipped = max(-32768.0, min(32767.0, scaled))
                return Int16(clipped)
            }
        }

        let ratio = outputRate / inputRate
        let outputCount = Int(Double(samples.count) * ratio)
        var output = [Int16](repeating: 0, count: outputCount)

        for i in 0..<outputCount {
            let inputIndex = Double(i) / ratio
            let idx1 = min(Int(inputIndex), samples.count - 1)
            let idx2 = min(idx1 + 1, samples.count - 1)
            let frac = Float(inputIndex - Double(idx1))

            // Linear interpolation
            let sample = samples[idx1] + frac * (samples[idx2] - samples[idx1])

            // Convert to Int16
            let scaled = sample * 32767.0
            let clipped = max(-32768.0, min(32767.0, scaled))
            output[i] = Int16(clipped)
        }

        return output
    }

    private func writeToFile(samples: [Int16]) {
        guard !samples.isEmpty else { return }

        fileLock.lock()
        defer { fileLock.unlock() }

        guard let audioFile = audioFile else { return }

        // Create buffer with Int16 samples
        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount) else {
            return
        }

        buffer.frameLength = frameCount

        // Copy samples to buffer
        if let int16Data = buffer.int16ChannelData {
            for i in 0..<samples.count {
                int16Data[0][i] = samples[i]
            }
        }

        do {
            try audioFile.write(from: buffer)
        } catch {
            logger.error("Failed to write audio: \(error.localizedDescription)")
        }
    }
}

// MARK: - SCStreamDelegate

extension SystemAudioCaptureService: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.error("Stream stopped with error: \(error.localizedDescription)")
        isCapturing = false
    }
}

// MARK: - SCStreamOutput

extension SystemAudioCaptureService: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .audio:
            processAudioSampleBuffer(sampleBuffer)
        case .screen, .microphone:
            // Ignore video and microphone (we use CoreAudioRecorder for mic)
            break
        @unknown default:
            break
        }
    }
}

// MARK: - Error Types

enum SystemAudioCaptureError: LocalizedError {
    case noPermission
    case noDisplayFound
    case alreadyCapturing
    case streamCreationFailed

    var errorDescription: String? {
        switch self {
        case .noPermission:
            return "Screen recording permission required for system audio capture. Enable in System Settings > Privacy & Security > Screen Recording"
        case .noDisplayFound:
            return "No display found for audio capture"
        case .alreadyCapturing:
            return "System audio capture already in progress"
        case .streamCreationFailed:
            return "Failed to create audio capture stream"
        }
    }
}
