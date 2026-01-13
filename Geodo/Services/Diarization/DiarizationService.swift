import Foundation
import AVFoundation
import FluidAudio
import os

/// Orchestrates speaker diarization for meeting recordings
@MainActor
class DiarizationService: ObservableObject {
    static let shared = DiarizationService()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "DiarizationService")
    private var offlineDiarizer: OfflineDiarizerManager?

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
    private func runDiarization(on audioURL: URL) async throws -> DiarizationResult {
        let startTime = Date()

        // Initialize diarizer if needed
        if offlineDiarizer == nil {
            logger.info("Initializing OfflineDiarizerManager...")
            offlineDiarizer = OfflineDiarizerManager(config: .default)
        }

        guard let diarizer = offlineDiarizer else {
            throw DiarizationError.diarizationFailed("Failed to initialize diarizer")
        }

        // Prepare models (downloads if needed, ~150MB first time)
        logger.info("Preparing diarization models...")
        try await diarizer.prepareModels()

        // Run diarization
        logger.info("Running speaker diarization on \(audioURL.lastPathComponent)...")
        let fluidResult = try await diarizer.process(audioURL)

        let processingDuration = Date().timeIntervalSince(startTime)

        // Map FluidAudio TimedSpeakerSegment to our DiarizationResult.SpeakerSegment
        let segments = fluidResult.segments.map { segment -> DiarizationResult.SpeakerSegment in
            // Parse speaker ID from string (e.g., "SPEAKER_0" -> 0)
            let speakerIdInt = parseSpeakerId(segment.speakerId)

            return DiarizationResult.SpeakerSegment(
                speakerId: speakerIdInt,
                startTime: TimeInterval(segment.startTimeSeconds),
                endTime: TimeInterval(segment.endTimeSeconds),
                confidence: segment.qualityScore
            )
        }

        // Count unique speakers
        let uniqueSpeakers = Set(segments.map { $0.speakerId }).count

        logger.info("Diarization complete: \(segments.count) segments, \(uniqueSpeakers) speakers in \(String(format: "%.2f", processingDuration))s")

        return DiarizationResult(
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
