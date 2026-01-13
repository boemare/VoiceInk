import Foundation

/// Represents a segment of transcription with speaker identification
struct TranscriptionSegment: Codable, Identifiable, Hashable {
    let id: UUID
    let speakerId: String         // "Me", "Speaker 1", "Speaker 2", etc.
    var speakerLabel: String?     // User-assigned name (e.g., "John")
    let text: String
    let startTime: TimeInterval   // Seconds from recording start
    let endTime: TimeInterval
    let confidence: Float?        // Diarization confidence (0-1)
    let source: AudioSource

    /// Source of the audio for this segment
    enum AudioSource: String, Codable {
        case mic      // User's microphone
        case system   // System audio (other meeting participants)
    }

    init(
        speakerId: String,
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        source: AudioSource,
        speakerLabel: String? = nil,
        confidence: Float? = nil
    ) {
        self.id = UUID()
        self.speakerId = speakerId
        self.speakerLabel = speakerLabel
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.source = source
    }

    /// Display name for the speaker (user label or speaker ID)
    var displayName: String {
        speakerLabel ?? speakerId
    }

    /// Duration of this segment in seconds
    var duration: TimeInterval {
        endTime - startTime
    }
}

/// Result from the diarization engine
struct DiarizationResult {
    let segments: [SpeakerSegment]
    let speakerCount: Int
    let processingDuration: TimeInterval

    struct SpeakerSegment {
        let speakerId: Int          // 0, 1, 2, etc.
        let startTime: TimeInterval
        let endTime: TimeInterval
        let confidence: Float
    }
}

/// Timestamped segment from Whisper transcription
struct WhisperTimestampedSegment {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}
