import Foundation
import AVFoundation
import FluidAudio
import os

/// Orchestrates speaker diarization for meeting recordings
@MainActor
class DiarizationService: ObservableObject {
    static let shared = DiarizationService()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "DiarizationService")

    @Published var isDiarizationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isDiarizationEnabled, forKey: "IsDiarizationEnabled")
        }
    }

    @Published var isProcessing = false
    @Published var progress: Double = 0.0

    private init() {
        self.isDiarizationEnabled = UserDefaults.standard.bool(forKey: "IsDiarizationEnabled")
    }

    /// Process dual-track recording with speaker diarization
    /// - Parameters:
    ///   - micAudioURL: URL to microphone audio (user's voice)
    ///   - systemAudioURL: URL to system audio (other participants)
    ///   - transcriptionService: Service to transcribe audio
    ///   - model: Transcription model to use
    /// - Returns: Array of conversation segments with speaker labels
    func processMeetingRecording(
        micAudioURL: URL,
        systemAudioURL: URL,
        transcribe: @escaping (URL) async throws -> String,
        transcribeWithTimestamps: @escaping (URL) async throws -> [WhisperTimestampedSegment]
    ) async throws -> [TranscriptionSegment] {
        isProcessing = true
        defer { isProcessing = false }

        logger.info("Starting diarization processing")

        // Step 1: Transcribe mic audio (always "Me")
        progress = 0.1
        logger.info("Transcribing mic audio...")
        let micText = try await transcribe(micAudioURL)
        let micDuration = try await getAudioDuration(url: micAudioURL)

        // Step 2: Transcribe system audio with timestamps
        progress = 0.3
        logger.info("Transcribing system audio with timestamps...")
        let systemTranscriptSegments = try await transcribeWithTimestamps(systemAudioURL)

        // Step 3: Run diarization on system audio
        progress = 0.5
        logger.info("Running speaker diarization on system audio...")
        let diarizationResult = try await runDiarization(on: systemAudioURL)

        // Step 4: Label system transcript segments with speaker IDs
        progress = 0.7
        logger.info("Assigning speaker labels...")
        let labeledSystemSegments = TranscriptMerger.assignSpeakerLabels(
            transcriptSegments: systemTranscriptSegments,
            diarizationResult: diarizationResult
        )

        // Step 5: Create mic segments
        progress = 0.8
        let micSegments = TranscriptMerger.createMicSegments(
            text: micText,
            duration: micDuration,
            systemSegments: labeledSystemSegments
        )

        // Step 6: Merge all segments by timestamp
        progress = 0.9
        logger.info("Merging transcripts...")
        let mergedSegments = TranscriptMerger.merge(
            micSegments: micSegments,
            systemSegments: labeledSystemSegments
        )

        progress = 1.0
        logger.info("Diarization complete: \(mergedSegments.count) segments, \(diarizationResult.speakerCount) speakers")

        return mergedSegments
    }

    /// Run speaker diarization on audio file using FluidAudio
    private func runDiarization(on audioURL: URL) async throws -> SpeakerDiarizationResult {
        let startTime = Date()
        logger.info("Running speaker diarization on \(audioURL.lastPathComponent)...")

        // Run heavy processing off the main actor
        let fluidResult = try await Task.detached(priority: .userInitiated) {
            let diarizer = OfflineDiarizerManager(config: .default)
            try await diarizer.prepareModels()
            return try await diarizer.process(audioURL)
        }.value

        let processingDuration = Date().timeIntervalSince(startTime)

        // Map FluidAudio TimedSpeakerSegment to our SpeakerDiarizationResult.SpeakerSegment
        let segments = fluidResult.segments.map { segment -> SpeakerDiarizationResult.SpeakerSegment in
            // Parse speaker ID from string (e.g., "SPEAKER_0" -> 0)
            let speakerIdInt = parseSpeakerId(segment.speakerId)

            return SpeakerDiarizationResult.SpeakerSegment(
                speakerId: speakerIdInt,
                startTime: TimeInterval(segment.startTimeSeconds),
                endTime: TimeInterval(segment.endTimeSeconds),
                confidence: segment.qualityScore
            )
        }

        // Count unique speakers
        let uniqueSpeakers = Set(segments.map { $0.speakerId }).count

        logger.info("Diarization complete: \(segments.count) segments, \(uniqueSpeakers) speakers in \(String(format: "%.2f", processingDuration))s")

        return SpeakerDiarizationResult(
            segments: segments,
            speakerCount: uniqueSpeakers,
            processingDuration: processingDuration
        )
    }

    /// Parse speaker ID from FluidAudio's string format (e.g., "SPEAKER_0" -> 0)
    private func parseSpeakerId(_ speakerId: String) -> Int {
        // Try to extract number from end of string
        if let match = speakerId.range(of: "\\d+$", options: .regularExpression),
           let id = Int(speakerId[match]) {
            return id
        }
        // Fallback: hash the string to get a consistent ID
        return abs(speakerId.hashValue) % 100
    }

    /// Get duration of audio file
    private func getAudioDuration(url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }
}

// MARK: - Errors

enum DiarizationError: LocalizedError {
    case modelNotFound(String)
    case invalidAudio
    case diarizationFailed(String)
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let model):
            return "Diarization model not found: \(model)"
        case .invalidAudio:
            return "Invalid audio format for diarization"
        case .diarizationFailed(let reason):
            return "Diarization failed: \(reason)"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}
