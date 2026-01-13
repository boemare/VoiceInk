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
    private var isTranscribing = false  // Prevent concurrent transcription

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

        // Wait for any in-progress transcription to complete
        while isTranscribing {
            try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        }

        // Transcribe any remaining audio in buffer (skip if too short)
        if audioBuffer.count > Int(sampleRate * 1.0) { // At least 1 second
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

        // Check if we have enough samples for a chunk and not already transcribing
        let samplesInCurrentChunk = audioBuffer.count
        if samplesInCurrentChunk >= minChunkSamples && !isTranscribing {
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
        isTranscribing = false
    }

    // MARK: - Private

    private func transcribeCurrentBuffer(isFinal: Bool) async {
        guard let transcribe = transcriptionCallback else { return }
        guard !isTranscribing else {
            logger.debug("Skipping chunk - transcription already in progress")
            return
        }

        isTranscribing = true
        defer { isTranscribing = false }

        let samplesToTranscribe = audioBuffer
        let startSample = lastChunkEndSample
        let endSample = startSample + samplesToTranscribe.count

        // Calculate timing
        let startTime = Double(startSample) / sampleRate
        let endTime = Double(endSample) / sampleRate

        // Clear buffer before transcribing (we've captured the samples)
        if isFinal {
            audioBuffer = []
            lastChunkEndSample = endSample
        } else {
            // Keep overlap samples for continuity
            if audioBuffer.count > overlapSamples {
                audioBuffer = Array(audioBuffer.suffix(overlapSamples))
                lastChunkEndSample = endSample - overlapSamples
            } else {
                audioBuffer = []
                lastChunkEndSample = endSample
            }
        }

        let currentChunkIndex = chunkIndex
        chunkIndex += 1

        logger.debug("Transcribing chunk \(currentChunkIndex): \(samplesToTranscribe.count) samples (\(String(format: "%.1f", startTime))s - \(String(format: "%.1f", endTime))s)")

        do {
            let text = try await transcribe(samplesToTranscribe)
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Filter out common whisper artifacts
            let cleanedText = cleanTranscriptionArtifacts(trimmedText)

            if !cleanedText.isEmpty {
                let chunk = TranscribedChunk(
                    text: cleanedText,
                    startTime: startTime,
                    endTime: endTime,
                    chunkIndex: currentChunkIndex
                )

                transcribedChunks.append(chunk)

                // Notify callback on main thread
                if let callback = onChunkTranscribed {
                    await MainActor.run {
                        callback(chunk)
                    }
                }

                logger.notice("Chunk \(currentChunkIndex) transcribed: \"\(cleanedText.prefix(50))\"")
            }
        } catch {
            logger.error("Failed to transcribe chunk \(currentChunkIndex): \(error.localizedDescription)")
        }
    }

    /// Clean common transcription artifacts from Whisper
    private func cleanTranscriptionArtifacts(_ text: String) -> String {
        var cleaned = text

        // Remove common Whisper artifacts
        let artifacts = [
            "[BLANK_AUDIO]",
            "[MUSIC]",
            "[APPLAUSE]",
            "(music)",
            "(applause)",
            "...",
            "Thank you for watching.",
            "Thanks for watching.",
            "Subscribe to my channel.",
            "Please subscribe.",
        ]

        for artifact in artifacts {
            cleaned = cleaned.replacingOccurrences(of: artifact, with: "", options: .caseInsensitive)
        }

        // Remove repeated phrases (common whisper hallucination)
        cleaned = removeRepeatedPhrases(cleaned)

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Remove phrases that repeat more than twice
    private func removeRepeatedPhrases(_ text: String) -> String {
        let words = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard words.count > 6 else { return text }

        // Check for repeating patterns of 2-4 words
        for patternLength in 2...4 {
            guard words.count >= patternLength * 3 else { continue }

            var i = 0
            var result: [String] = []
            var skipUntil = -1

            while i < words.count {
                if i < skipUntil {
                    i += 1
                    continue
                }

                // Check if the next patternLength words repeat
                if i + patternLength * 2 <= words.count {
                    let pattern = Array(words[i..<(i + patternLength)])
                    var repeatCount = 1

                    var j = i + patternLength
                    while j + patternLength <= words.count {
                        let nextSegment = Array(words[j..<(j + patternLength)])
                        if nextSegment == pattern {
                            repeatCount += 1
                            j += patternLength
                        } else {
                            break
                        }
                    }

                    if repeatCount >= 3 {
                        // Keep only one instance
                        result.append(contentsOf: pattern)
                        skipUntil = j
                        i = j
                        continue
                    }
                }

                result.append(words[i])
                i += 1
            }

            if result.count < words.count {
                return result.joined(separator: " ")
            }
        }

        return text
    }
}
