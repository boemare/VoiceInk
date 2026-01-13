import Foundation
import SwiftData

@Model
final class Note {
    var id: UUID
    var text: String
    var enhancedText: String?
    var timestamp: Date
    var duration: TimeInterval
    var audioFileURL: String?
    var transcriptionModelName: String?
    var aiEnhancementModelName: String?
    var promptName: String?
    var transcriptionDuration: TimeInterval?
    var enhancementDuration: TimeInterval?

    // Meeting-specific fields
    var isMeeting: Bool
    var systemAudioFileURL: String?
    var sourceApp: String?
    var participants: [String]?

    // Diarization fields
    var conversationSegmentsData: Data?  // JSON-encoded [TranscriptionSegment]
    var speakerMapData: Data?            // JSON-encoded [String: String] for speaker labels
    var hasDiarization: Bool

    // Computed property for decoded conversation segments
    var conversationSegments: [TranscriptionSegment]? {
        get {
            guard let data = conversationSegmentsData else { return nil }
            return try? JSONDecoder().decode([TranscriptionSegment].self, from: data)
        }
        set {
            conversationSegmentsData = try? JSONEncoder().encode(newValue)
        }
    }

    // Computed property for speaker label mapping
    var speakerMap: [String: String]? {
        get {
            guard let data = speakerMapData else { return nil }
            return try? JSONDecoder().decode([String: String].self, from: data)
        }
        set {
            speakerMapData = try? JSONEncoder().encode(newValue)
        }
    }

    init(text: String,
         duration: TimeInterval,
         enhancedText: String? = nil,
         audioFileURL: String? = nil,
         transcriptionModelName: String? = nil,
         aiEnhancementModelName: String? = nil,
         promptName: String? = nil,
         transcriptionDuration: TimeInterval? = nil,
         enhancementDuration: TimeInterval? = nil,
         isMeeting: Bool = false,
         systemAudioFileURL: String? = nil,
         sourceApp: String? = nil,
         participants: [String]? = nil,
         conversationSegments: [TranscriptionSegment]? = nil,
         hasDiarization: Bool = false) {
        self.id = UUID()
        self.text = text
        self.enhancedText = enhancedText
        self.timestamp = Date()
        self.duration = duration
        self.audioFileURL = audioFileURL
        self.transcriptionModelName = transcriptionModelName
        self.aiEnhancementModelName = aiEnhancementModelName
        self.promptName = promptName
        self.transcriptionDuration = transcriptionDuration
        self.enhancementDuration = enhancementDuration
        self.isMeeting = isMeeting
        self.systemAudioFileURL = systemAudioFileURL
        self.sourceApp = sourceApp
        self.participants = participants
        self.hasDiarization = hasDiarization
        if let segments = conversationSegments {
            self.conversationSegmentsData = try? JSONEncoder().encode(segments)
        }
    }
}
