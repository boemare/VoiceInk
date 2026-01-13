import Foundation
import os

/// Represents a transcribed audio chunk with timing information
struct TranscribedChunk: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let chunkIndex: Int
}

/// Actor-based service for real-time chunked transcription during recording
/// Buffers incoming audio samples and transcribes in chunks for live display
actor ChunkedTranscriptionService {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ChunkedTranscriptionService")

    // Configuration
    private let chunkDurationSeconds: TimeInterval = 4.0  // Transcribe every 4 seconds
    private let overlapDurationSeconds: TimeInterval = 0.5  // Overlap between chunks for continuity
    private let sampleRate: Double = 16000.0  // Expected sample rate (16kHz)

    // Audio buffer
    private var audioBuffer: [Float] = []
    private var totalSamplesReceived: Int = 0
    private var lastChunkEndSample: Int = 0
    private var chunkIndex: Int = 0

    // Transcription
    private var transcriptionCallback: (([Float]) async throws -> String)?
    private var isRunning = false

    // Results
    private var transcribedChunks: [TranscribedChunk] = []
    private var onChunkTranscribed: ((TranscribedChunk) -> Void)?

    // Minimum samples for a chunk (chunkDuration * sampleRate)
    private var minChunkSamples: Int {
        Int(chunkDurationSeconds * sampleRate)
    }

    private var overlapSamples: Int {
        Int(overlapDurationSeconds * sampleRate)
    }

    /// Start the chunked transcription service
    /// - Parameters:
    ///   - transcribe: Closure that takes Float samples and returns transcribed text
    ///   - onChunk: Callback when a new chunk is transcribed
    func start(
        transcribe: @escaping ([Float]) async throws -> String,
        onChunk: @escaping (TranscribedChunk) -> Void
    ) {
        logger.notice("Starting chunked transcription service")
        reset()
        self.transcriptionCallback = transcribe
        self.onChunkTranscribed = onChunk
        self.isRunning = true
    }

    /// Stop the service and transcribe any remaining audio
    func stop() async {
        guard isRunning else { return }
        isRunning = false

        logger.notice("Stopping chunked transcription service")

        // Transcribe any remaining audio in buffer
        if audioBuffer.count > Int(sampleRate * 0.5) { // At least 0.5 seconds
            await transcribeCurrentBuffer(isFinal: true)
        }

        transcriptionCallback = nil
        onChunkTranscribed = nil
    }

    /// Feed audio samples to the buffer
    /// - Parameter samples: Float audio samples at 16kHz
    func feedSamples(_ samples: [Float]) async {
        guard isRunning else { return }

        audioBuffer.append(contentsOf: samples)
        totalSamplesReceived += samples.count

        // Check if we have enough samples for a chunk
        let samplesInCurrentChunk = audioBuffer.count
        if samplesInCurrentChunk >= minChunkSamples {
            await transcribeCurrentBuffer(isFinal: false)
        }
    }

    /// Get all transcribed chunks so far
    func getChunks() -> [TranscribedChunk] {
        return transcribedChunks
    }

    /// Get the full transcript combining all chunks
    func getFullTranscript() -> String {
        return transcribedChunks.map { $0.text }.joined(separator: " ")
    }

    /// Reset the service state
    func reset() {
        audioBuffer = []
        totalSamplesReceived = 0
        lastChunkEndSample = 0
        chunkIndex = 0
        transcribedChunks = []
    }

    // MARK: - Private

    private func transcribeCurrentBuffer(isFinal: Bool) async {
        guard let transcribe = transcriptionCallback else { return }

        let samplesToTranscribe = audioBuffer
        let startSample = lastChunkEndSample
        let endSample = startSample + samplesToTranscribe.count

        // Calculate timing
        let startTime = Double(startSample) / sampleRate
        let endTime = Double(endSample) / sampleRate

        logger.debug("Transcribing chunk \(self.chunkIndex): \(samplesToTranscribe.count) samples (\(String(format: "%.1f", startTime))s - \(String(format: "%.1f", endTime))s)")

        do {
            let text = try await transcribe(samplesToTranscribe)
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

            if !trimmedText.isEmpty {
                let chunk = TranscribedChunk(
                    text: trimmedText,
                    startTime: startTime,
                    endTime: endTime,
                    chunkIndex: chunkIndex
                )

                transcribedChunks.append(chunk)

                // Notify callback on main thread
                if let callback = onChunkTranscribed {
                    await MainActor.run {
                        callback(chunk)
                    }
                }

                logger.notice("Chunk \(self.chunkIndex) transcribed: \"\(trimmedText.prefix(50))...\"")
            }
        } catch {
            logger.error("Failed to transcribe chunk \(self.chunkIndex): \(error.localizedDescription)")
        }

        // Update state for next chunk
        chunkIndex += 1

        if isFinal {
            audioBuffer = []
            lastChunkEndSample = endSample
        } else {
            // Keep overlap samples for continuity
            if audioBuffer.count > overlapSamples {
                let keepFrom = audioBuffer.count - overlapSamples
                audioBuffer = Array(audioBuffer.suffix(overlapSamples))
                lastChunkEndSample = endSample - overlapSamples
            } else {
                audioBuffer = []
                lastChunkEndSample = endSample
            }
        }
    }
}

// MARK: - Sample Buffer for Real-time Streaming

/// Thread-safe buffer for streaming audio samples from the recording callback
class AudioSampleBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var callback: (([Float]) -> Void)?

    /// Set the callback to receive samples
    func setCallback(_ callback: @escaping ([Float]) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        self.callback = callback
    }

    /// Clear the callback
    func clearCallback() {
        lock.lock()
        defer { lock.unlock() }
        self.callback = nil
    }

    /// Append samples (called from audio callback thread)
    func append(_ newSamples: [Float]) {
        lock.lock()
        let cb = callback
        lock.unlock()

        // Call callback immediately with new samples
        cb?(newSamples)
    }
}
