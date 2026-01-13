import Foundation

/// Merges mic and system audio transcripts into a chronological conversation
struct TranscriptMerger {

    /// Merge mic segments (labeled as "Me") with system segments (labeled by speaker)
    /// Returns segments sorted by start time
    static func merge(
        micSegments: [TranscriptionSegment],
        systemSegments: [TranscriptionSegment]
    ) -> [TranscriptionSegment] {
        var allSegments = micSegments + systemSegments

        // Sort by start time
        allSegments.sort { $0.startTime < $1.startTime }

        // Merge adjacent segments from same speaker (within 1 second gap)
        return mergeAdjacentSegments(allSegments)
    }

    /// Merge adjacent segments from the same speaker if gap is small
    private static func mergeAdjacentSegments(_ segments: [TranscriptionSegment]) -> [TranscriptionSegment] {
        guard !segments.isEmpty else { return [] }

        var merged: [TranscriptionSegment] = []

        for segment in segments {
            if let last = merged.last,
               last.speakerId == segment.speakerId,
               last.source == segment.source,
               segment.startTime - last.endTime < 1.0 {  // 1 second gap threshold
                // Extend previous segment
                let extended = TranscriptionSegment(
                    speakerId: last.speakerId,
                    text: last.text + " " + segment.text,
                    startTime: last.startTime,
                    endTime: segment.endTime,
                    source: last.source,
                    speakerLabel: last.speakerLabel,
                    confidence: last.confidence
                )
                merged[merged.count - 1] = extended
            } else {
                merged.append(segment)
            }
        }

        return merged
    }

    /// Assign speaker labels from diarization result to transcript segments
    /// Based on timestamp overlap between diarization and transcription
    static func assignSpeakerLabels(
        transcriptSegments: [WhisperTimestampedSegment],
        diarizationResult: DiarizationResult
    ) -> [TranscriptionSegment] {
        var labeled: [TranscriptionSegment] = []

        for segment in transcriptSegments {
            // Find the speaker active during this segment's midpoint
            let midpoint = (segment.startTime + segment.endTime) / 2
            let speakerId = findSpeaker(at: midpoint, in: diarizationResult.segments)
            let confidence = findConfidence(at: midpoint, in: diarizationResult.segments)

            let labeledSegment = TranscriptionSegment(
                speakerId: "Speaker \(speakerId + 1)",
                text: segment.text,
                startTime: segment.startTime,
                endTime: segment.endTime,
                source: .system,
                confidence: confidence
            )
            labeled.append(labeledSegment)
        }

        return labeled
    }

    /// Find which speaker is active at a given timestamp
    private static func findSpeaker(
        at time: TimeInterval,
        in segments: [DiarizationResult.SpeakerSegment]
    ) -> Int {
        for segment in segments {
            if time >= segment.startTime && time <= segment.endTime {
                return segment.speakerId
            }
        }
        return 0  // Default to Speaker 0 if no match
    }

    /// Find confidence for speaker at given timestamp
    private static func findConfidence(
        at time: TimeInterval,
        in segments: [DiarizationResult.SpeakerSegment]
    ) -> Float? {
        for segment in segments {
            if time >= segment.startTime && time <= segment.endTime {
                return segment.confidence
            }
        }
        return nil
    }

    /// Create "Me" segments from mic transcription
    /// Splits mic transcript to interleave with system segments
    static func createMicSegments(
        text: String,
        duration: TimeInterval,
        systemSegments: [TranscriptionSegment]
    ) -> [TranscriptionSegment] {
        // If no system segments, return single "Me" segment
        guard !systemSegments.isEmpty else {
            return [TranscriptionSegment(
                speakerId: "Me",
                text: text,
                startTime: 0,
                endTime: duration,
                source: .mic
            )]
        }

        // For now, create a single "Me" segment
        // Future enhancement: use VAD or word-level timestamps to split mic audio
        return [TranscriptionSegment(
            speakerId: "Me",
            text: text,
            startTime: 0,
            endTime: duration,
            source: .mic
        )]
    }
}
